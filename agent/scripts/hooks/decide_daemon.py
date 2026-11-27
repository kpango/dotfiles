#!/usr/bin/env python3
"""decide.py の判定を Unix ソケット常駐デーモンで高速化する(hook 判定の fast path)。

  decide_daemon.py --daemon   フォアグラウンドで待受(systemd Type=simple 用。自己 fork しない)
  decide_daemon.py --ping     生死確認 (応答すれば "pong" / exit 0、なければ exit 1)
  decide_daemon.py --status   稼働状況を JSON で表示 (exit 0 / 1)
  decide_daemon.py --stop     自分(同 uid)のデーモンへ停止要求 (kill はしない)
  decide_daemon.py --query    stdin の判定リクエスト JSON をデーモンへ送り結果 JSON を表示
                              (デーモンを使えない/要求が不適格なら exit 3。インプロセスへは落とさない)

ソケット: ${AGENT_DECIDE_SOCK:-${XDG_RUNTIME_DIR:-/tmp/uid-$UID}/agent-decide.sock} (mode 0600)。
親ディレクトリは自分所有・group/other 権限なし(0700 相当)でなければ起動も接続も拒否する。

プロトコル: 1 リクエスト 1 行の JSON
  {"op": "decide"|"ping"|"status"|"stop", "req": {...}, "env": {...全環境変数...}, "cwd": "<クライアントの cwd>"}
を改行終端で送り、1 行の JSON ({"ok": bool, ...}) を受け取る。JSON 以外 (pickle 等) は扱わない。
リクエスト上限は decide.MAX_REQ_BYTES。接続元 uid は SO_PEERCRED で検証し、自分以外は応答せず切断する。

判定の同一性 — fork-per-request: 親(イベントループ)は import 済みのコードを持つだけで判定しない。
decide 要求ごとに os.fork() し、子が (a) クライアントの cwd へ chdir (b) 環境変数をクライアントの
os.environ へ丸ごと置換 (c) decide.dispatch() を in-process と同じコード・同じルール読込で評価し、
結果をパイプで親へ返して _exit する。これで cwd・環境・相対パス・`git -C`・遅い git・握り潰される例外が
in-process と同一になる。親は deadline(CHILD_DEADLINE_S)を超えた子を SIGKILL して waitpid し、
{"ok": false} を返す(deadline 後の結果は絶対に採用しない。クライアントは in-process へ落ちる)。
同時に動かす子は MAX_CHILDREN まで(超過は {"ok": false, "error": "busy"})。子は自分自身にも
alarm を仕掛け、親が死んでも残らない。
応答には rule_engine.py / decide.py(ホットリロード後の内容)と decide_daemon.py(起動時に固定した
ハッシュ)から作るコード署名 "sig" を載せ、クライアントは自分のディスク上のコードと一致しない応答を
捨てる(古い/別コードのデーモンを使わない)。
D2 のルール無効化: 親は decide 要求で参照される rules_file / vald_rules_file を毎回 stat
(mtime_ns+ctime_ns+size+ino+dev)し、以前ロードに成功したルール/コード(rule_engine.py・decide.py)が壊れた状態に
変わった(再ロード失敗)場合は fail-closed(decision "block")を返す。一度も正常ロードできていないルールは
子が in-process と同じ読み込みをして既定挙動に従う。コードは stat して importlib.reload する。
イベントループは単一スレッドの selectors で、無言/低速クライアントは他の要求を待たせない
(接続ごと CONN_TIMEOUT・同時接続上限 MAX_CONNS)。親側の処理(再ロード等)は SIGALRM の deadline、
さらに watchdog スレッドが WATCHDOG_S 超の停止を検知して自己終了し systemd に再起動させる。
多重起動は flock、古いソケットの掃除はロック取得後(=他のデーモンが存在しない)にのみ行う。
"""
from __future__ import annotations

import fcntl
import hashlib
import importlib
import json
import os
import selectors
import signal
import socket
import stat
import struct
import sys
import threading
import time
import warnings
from pathlib import Path

# 親はスレッド(watchdog)を持つ。子は fork 直後に import も lock も使わず評価するので警告は抑止する。
warnings.filterwarnings("ignore", message=".*fork.*", category=DeprecationWarning)

HERE = Path(__file__).resolve().parent


def _sig(path) -> tuple | None:
    try:
        st = os.stat(path)
    except OSError:
        return None
    return (st.st_mtime_ns, st.st_ctime_ns, st.st_size, st.st_ino, st.st_dev)


CODE_FILES = [HERE / "rule_engine.py", HERE / "decide.py"]
# import より前に取得する(import 後に取ると、その間の変更を見逃す)。
_BOOT_SIGS = tuple(_sig(p) for p in CODE_FILES)
# decide_daemon.py 自身は hot-reload しない: 起動時のハッシュを固定し、ディスクが編集されたら署名が不一致になる。
try:
    _SELF_HASH = hashlib.sha256(Path(__file__).resolve().read_bytes()).hexdigest()
except OSError:
    _SELF_HASH = "unreadable"

sys.path.insert(0, str(HERE))
import decide  # noqa: E402
import rule_engine  # noqa: E402

CONN_TIMEOUT = 1.0
PARENT_DEADLINE_S = 3.0
CHILD_DEADLINE_S = 3.0
WATCHDOG_S = 10.0
MAX_CONNS = 64
MAX_CHILDREN = 8
MAX_CHILD_OUTPUT = 4 * 1024 * 1024
MAX_JSON_CACHE = 64
MAX_RULES_BYTES = 4 * 1024 * 1024
MAX_PATH_LEN = 4096
DEFAULT_RULE_FILES = [
    HERE.parents[1] / "security-rules.json",
    HERE.parents[1] / "vald-law-rules.json",
    HERE.parents[1] / "write-scope-rules.json",
]


class ReloadError(Exception):
    """以前ロード済みのルール/コードの再ロードに失敗した。fail-closed(block)で応答する。"""


class RequestTimeout(BaseException):
    """親側処理の deadline。BaseException なので途中の `except Exception` に握り潰されない。"""


class State:
    def __init__(self) -> None:
        self.started = time.time()
        self.requests = 0
        self.reloads = 0
        self.stop = False
        self.loaded_sigs: tuple | None = _BOOT_SIGS
        self.broken_sigs: tuple | None = None
        self.json_cache: dict[str, dict] = {}
        self.hashes: dict[str, str] = {}
        self.busy_since: float | None = None
        self.children = 0


STATE = State()


def code_sig() -> str:
    return decide.code_signature(HERE, frozen={**STATE.hashes, "decide_daemon.py": _SELF_HASH})


def _hash_file_blobs() -> dict[str, str]:
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in CODE_FILES}


# --- ルール JSON の「以前ロードに成功したか」ガード(判定データは子が in-process と同じ方法で読む) --------

def _read_rules_file(path: str):
    """O_NONBLOCK で開き、通常ファイル・サイズ上限を確認して JSON を読む。"""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_RULES_BYTES:
            raise ValueError("not a regular file or too large")
        raw = b""
        while len(raw) <= MAX_RULES_BYTES:
            chunk = os.read(fd, 1 << 20)
            if not chunk:
                break
            raw += chunk
        if len(raw) > MAX_RULES_BYTES:
            raise ValueError("too large")
    finally:
        os.close(fd)
    return json.loads(raw.decode("utf-8"))


def _read_json_stable(path: str):
    """stat→read→stat で書き込み途中を検知し、最大 3 回リトライ。(sig, data) を返す。"""
    last_exc: Exception | None = None
    for _ in range(3):
        before = _sig(path)
        if before is None:
            raise FileNotFoundError(path)
        try:
            data = _read_rules_file(path)
        except Exception as e:  # 構文エラー・書き込み途中・通常ファイルでない
            last_exc = e
            if _sig(path) == before:
                raise
            continue
        if _sig(path) == before:
            return before, data
    raise last_exc or RuntimeError("unstable file")


def guard_rules_file(path) -> None:
    """以前正常にロードできたルールが壊れていれば ReloadError(fail-closed)。それ以外は何もしない
    (判定データそのものは子が in-process と同じ読み込みで得る)。"""
    if not isinstance(path, str) or not path or "\0" in path or len(path) > MAX_PATH_LEN:
        return
    ent = STATE.json_cache.get(path)
    sig = _sig(path)
    if ent is not None and sig is not None and ent["sig"] == sig:
        if not ent["ok"] and ent["had_good"]:
            raise ReloadError(f"rules reload failed: {path}")
        return
    had_good = bool(ent and ent["had_good"])
    try:
        new_sig, _data = _read_json_stable(path)
    except Exception:
        STATE.json_cache[path] = {"sig": sig, "ok": False, "had_good": had_good}
        if had_good:
            raise ReloadError(f"rules reload failed: {path}")
        return
    if path not in STATE.json_cache and len(STATE.json_cache) >= MAX_JSON_CACHE:
        STATE.json_cache.pop(next(iter(STATE.json_cache)))
    STATE.json_cache[path] = {"sig": new_sig, "ok": True, "had_good": True}
    STATE.reloads += 1


# --- コード(rule_engine.py / decide.py)のホットリロード ---------------------------

def ensure_code_fresh() -> None:
    sigs = tuple(_sig(p) for p in CODE_FILES)
    if sigs == STATE.loaded_sigs:
        return
    if sigs == STATE.broken_sigs:
        raise ReloadError("code reload failed (unchanged since failure)")
    try:
        if any(s is None for s in sigs):
            raise FileNotFoundError("rule code missing")
        blobs = [p.read_bytes() for p in CODE_FILES]
        for p, b in zip(CODE_FILES, blobs):  # 構文エラーを reload 前に検出(モジュールを壊さない)
            compile(b, str(p), "exec")
        importlib.reload(rule_engine)
        importlib.reload(decide)
        STATE.hashes = {p.name: hashlib.sha256(b).hexdigest() for p, b in zip(CODE_FILES, blobs)}
        warm()
    except Exception as e:
        STATE.broken_sigs = sigs
        raise ReloadError(f"code reload failed: {e}") from e
    STATE.loaded_sigs = sigs
    STATE.broken_sigs = None
    STATE.reloads += 1


def warm() -> None:
    """親で 1 度 dispatch を走らせ、正規表現のコンパイル結果(re のキャッシュ)等を温める。子は fork で
    それを継承するので、要求ごとに全ルールの regex をコンパイルし直さずに済む(判定結果には影響しない)。
    副作用のない入力のみ(git を起動しない・書込みをしない)。失敗しても無視する。"""
    sec, vald, ws = (str(p) for p in DEFAULT_RULE_FILES)
    for req in (
        {"family": "security_shell", "command": "ls", "cwd": "/", "rules_file": sec, "resolve_command_target": True},
        {"family": "security_write", "file_path": "/tmp/x", "cwd": "/", "home": "/", "rules_file": sec},
        {"family": "write_scope", "file_path": "/tmp/x", "cwd": "/", "home": "/", "rules_file": ws},
        {"family": "vald_law1", "file_path": "/tmp/x.go", "vald_rules_file": vald},
        {"family": "vald_law2", "command": "ls", "cwd": "/", "vald_rules_file": vald, "scope_mode": "none"},
        {"family": "vald_law345", "file_path": "/tmp/x.go", "content": "package x\n", "vald_rules_file": vald, "scope_mode": "none"},
    ):
        try:
            decide.dispatch(req)
        except Exception:
            pass


def fail_closed(reason: str) -> dict:
    return {"ok": True, "sig": code_sig(),
            "result": {"decision": "block", "reason": f"agent-decide: {reason} (fail-closed)", "matches": []}}


def _on_alarm(_s, _f):
    raise RequestTimeout()


def status_payload(sock_path: str) -> dict:
    return {
        "ok": True,
        "pid": os.getpid(),
        "uid": os.getuid(),
        "socket": sock_path,
        "uptime_s": round(time.time() - STATE.started, 3),
        "requests": STATE.requests,
        "reloads": STATE.reloads,
        "code_broken": STATE.broken_sigs is not None,
        "cached_rule_files": len(STATE.json_cache),
        "children": STATE.children,
        "sig": code_sig(),
        "cwd": os.getcwd(),
    }


# --- 子プロセス(fork-per-request) -----------------------------------------------------

def _child_main(req, env: dict, pcwd: str, wfd: int) -> None:
    """fork 直後の子。クライアントの cwd・環境を再現して評価し、結果を wfd へ書いて _exit する。"""
    code = 1
    try:
        for s in (signal.SIGALRM, signal.SIGTERM, signal.SIGINT):
            signal.signal(s, signal.SIG_DFL)
        signal.alarm(int(CHILD_DEADLINE_S) + 3)  # 親が死んでも残らない
        for fd in [int(x) for x in os.listdir("/proc/self/fd")]:
            if fd > 2 and fd != wfd:
                try:
                    os.close(fd)
                except OSError:
                    pass
        os.chdir(pcwd)
        os.environ.clear()
        os.environ.update(env)
        out = {"ok": True, "result": decide.dispatch(req)}
        code = 0
    except BaseException as e:  # noqa: BLE001 — 子は何があっても親へ ok:false を返して終わる
        out = {"ok": False, "error": f"child error: {type(e).__name__}"}
    try:
        data = json.dumps(out).encode("utf-8")
        view = memoryview(data)
        while view:
            n = os.write(wfd, view)
            view = view[n:]
    except BaseException:  # noqa: BLE001
        pass
    try:
        os.close(wfd)  # 親へ EOF を先に伝える(プロセス終了処理の完了を待たせない)
    except OSError:
        pass
    os._exit(code)


def start_decide(msg: dict) -> tuple[dict | None, dict | None]:
    """decide 要求を検証して子を起動。(即時応答, 子情報) のどちらか一方を返す。"""
    req, env, pcwd = msg.get("req"), msg.get("env"), msg.get("cwd")
    if (not isinstance(req, dict) or not isinstance(env, dict) or not isinstance(pcwd, str) or not pcwd.startswith("/")
            or not all(isinstance(k, str) and isinstance(v, str) and "\0" not in k + v and "=" not in k for k, v in env.items())):
        return {"ok": False, "error": "bad request"}, None
    for k in ("rules_file", "vald_rules_file"):
        v = req.get(k)
        if k in req and (not isinstance(v, str) or not v or "\0" in v or len(v) > MAX_PATH_LEN):
            return {"ok": False, "error": "bad rules path"}, None
    STATE.busy_since = time.monotonic()
    signal.setitimer(signal.ITIMER_REAL, PARENT_DEADLINE_S)
    try:
        ensure_code_fresh()
        for k in ("rules_file", "vald_rules_file"):
            v = req.get(k)
            if isinstance(v, str) and v and not v.startswith("/"):
                v = os.path.join(pcwd, v)  # クライアントの cwd 基準
            guard_rules_file(v)
    except ReloadError as e:
        return fail_closed(str(e)), None
    except RequestTimeout:
        return {"ok": False, "error": "timeout"}, None
    except Exception as e:
        return {"ok": False, "error": f"pre-check error: {type(e).__name__}"}, None
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        STATE.busy_since = None
    if STATE.children >= MAX_CHILDREN:
        return {"ok": False, "error": "busy"}, None
    rfd, wfd = os.pipe()
    try:
        pid = os.fork()
    except OSError:
        os.close(rfd)
        os.close(wfd)
        return {"ok": False, "error": "fork failed"}, None
    if pid == 0:
        os.close(rfd)
        _child_main(req, env, pcwd, wfd)  # 戻らない
    os.close(wfd)
    os.set_blocking(rfd, False)
    STATE.children += 1
    return None, {"pid": pid, "fd": rfd, "buf": bytearray(), "deadline": time.monotonic() + CHILD_DEADLINE_S}


def reap_child(child: dict, kill: bool) -> None:
    """子を必ず wait する(zombie を残さない)。kill=True なら SIGKILL してから。"""
    if child.get("reaped"):
        return
    child["reaped"] = True
    STATE.children -= 1
    try:
        os.close(child["fd"])
    except OSError:
        pass
    try:
        if kill:
            os.kill(child["pid"], signal.SIGKILL)
        os.waitpid(child["pid"], 0)
    except (ChildProcessError, ProcessLookupError, OSError):
        pass


# --- ソケットサーバ (selectors, 単一スレッド) -----------------------------------------

def _peer_uid_ok(conn: socket.socket) -> bool:
    cred = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    _pid, uid, _gid = struct.unpack("3i", cred)
    return uid == os.getuid()


def _send(conn: socket.socket, obj: dict) -> None:
    conn.setblocking(True)
    conn.settimeout(CONN_TIMEOUT)
    conn.sendall((json.dumps(obj) + "\n").encode("utf-8"))


def event_loop(srv: socket.socket, sock_path: str) -> None:
    sel = selectors.DefaultSelector()
    srv.setblocking(False)
    sel.register(srv, selectors.EVENT_READ, None)
    conns: dict[socket.socket, dict] = {}  # conn -> {"buf", "deadline", "child"}

    def drop(c: socket.socket) -> None:
        st = conns.pop(c, None)
        if st and st.get("child"):
            ch = st["child"]
            try:
                sel.unregister(ch["fd"])
            except Exception:
                pass
            reap_child(ch, kill=True)
        try:
            sel.unregister(c)
        except Exception:
            pass
        try:
            c.close()
        except Exception:
            pass

    def finish(c: socket.socket, resp: dict) -> None:
        try:
            _send(c, resp)
        except Exception:
            pass
        drop(c)

    def handle_line(c: socket.socket, line: bytes) -> None:
        try:
            msg = json.loads(line.decode("utf-8"))
            if not isinstance(msg, dict):
                raise ValueError
        except Exception:
            return finish(c, {"ok": False, "error": "invalid json"})
        op = msg.get("op")
        STATE.requests += 1
        if op == "decide":
            immediate, child = start_decide(msg)
            if immediate is not None:
                return finish(c, immediate)
            conns[c]["child"] = child
            try:
                sel.unregister(c)  # 以降この接続では読まない(子の結果待ち)
            except Exception:
                pass
            sel.register(child["fd"], selectors.EVENT_READ, c)
            return None
        if op == "ping":
            return finish(c, {"ok": True, "pong": True})
        if op == "status":
            return finish(c, status_payload(sock_path))
        if op == "stop":
            STATE.stop = True
            return finish(c, {"ok": True, "stopping": True})
        return finish(c, {"ok": False, "error": "unknown op"})

    while not STATE.stop:
        for key, _ in sel.select(0.2):
            if key.data is None:
                try:
                    c, _a = srv.accept()
                except OSError:
                    continue
                try:
                    if len(conns) >= MAX_CONNS or not _peer_uid_ok(c):
                        c.close()  # 応答せず切断
                        continue
                    c.setblocking(False)
                    conns[c] = {"buf": bytearray(), "deadline": time.monotonic() + CONN_TIMEOUT, "child": None}
                    sel.register(c, selectors.EVENT_READ, True)
                except Exception:
                    drop(c)
                continue
            if key.data is True:  # クライアント接続の読み取り
                c = key.fileobj
                try:
                    chunk = c.recv(65536)
                except (BlockingIOError, InterruptedError):
                    continue
                except OSError:
                    drop(c)
                    continue
                if not chunk:
                    drop(c)
                    continue
                buf = conns[c]["buf"]
                buf += chunk
                try:
                    if len(buf) > decide.MAX_REQ_BYTES + 1:
                        finish(c, {"ok": False, "error": "request too large"})
                    elif b"\n" in buf:
                        handle_line(c, bytes(buf).split(b"\n", 1)[0])
                except Exception:
                    drop(c)  # 1 要求の失敗でデーモンを落とさない
                continue
            c = key.data  # 子のパイプ
            st = conns.get(c)
            if not st or not st.get("child"):
                continue
            ch = st["child"]
            try:
                chunk = os.read(ch["fd"], 65536)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                chunk = b""
            if chunk:
                ch["buf"] += chunk
                if len(ch["buf"]) > MAX_CHILD_OUTPUT:
                    finish(c, {"ok": False, "error": "child output too large"})
                continue
            # EOF: 子が結果を書き終えた。deadline 内に完了した結果だけを採用する。
            # 応答を先に返し、waitpid(終了処理の完了待ち)は finish() -> drop() が応答後に行う。
            try:
                sel.unregister(ch["fd"])
            except Exception:
                pass
            try:
                out = json.loads(bytes(ch["buf"]).decode("utf-8"))
                resp = ({"ok": True, "sig": code_sig(), "result": out["result"]} if out.get("ok") is True
                        else {"ok": False, "error": "child failed"})
            except Exception:
                resp = {"ok": False, "error": "child produced no result"}
            finish(c, resp)
        now = time.monotonic()
        for c, st in list(conns.items()):
            ch = st.get("child")
            if ch is not None and now > ch["deadline"]:
                finish(c, {"ok": False, "error": "timeout"})  # drop() が SIGKILL + waitpid。結果は採用しない
            elif ch is None and st["deadline"] < now:
                drop(c)  # 無言/低速クライアントは他の要求を待たせず切る
    for c in list(conns):
        drop(c)


def _watchdog() -> None:
    while True:
        time.sleep(1.0)
        bs = STATE.busy_since
        if bs is not None and time.monotonic() - bs > WATCHDOG_S:
            os._exit(70)  # 応答不能: systemd(Restart=on-failure) に再起動させる


def _prepare_dir(sock_path: str) -> None:
    d = os.path.dirname(sock_path)
    default_dir = f"/tmp/uid-{os.getuid()}"
    if not os.path.lexists(d) and d == default_dir:
        os.mkdir(d, 0o700)
    st = os.lstat(d)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise OSError(f"refusing unsafe socket directory {d} (need own dir, mode 0700)")


def run_daemon() -> int:
    sock_path = decide.sock_path()
    try:
        _prepare_dir(sock_path)
    except OSError as e:
        print(f"agent-decide: socket dir error: {e}", file=sys.stderr)
        return 2
    lock_fd = os.open(sock_path + ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    st = os.fstat(lock_fd)
    if st.st_uid != os.getuid() or not stat.S_ISREG(st.st_mode):
        print("agent-decide: unsafe lock file", file=sys.stderr)
        return 2
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("agent-decide: already running", file=sys.stderr)
        return 1
    # ここまで来れば他に生きているデーモンは居ない: 自分所有の古いソケットだけ掃除する。
    try:
        sst = os.lstat(sock_path)
    except FileNotFoundError:
        pass
    else:
        if stat.S_ISSOCK(sst.st_mode) and sst.st_uid == os.getuid():
            os.unlink(sock_path)
        else:
            print(f"agent-decide: {sock_path} exists and is not our socket", file=sys.stderr)
            return 2

    os.chdir("/")  # 判定は子がクライアントの cwd で行う。親の cwd は無関係にしておく。
    try:
        STATE.hashes = _hash_file_blobs()
    except OSError as e:
        print(f"agent-decide: cannot read rule code: {e}", file=sys.stderr)
        return 2
    if tuple(_sig(p) for p in CODE_FILES) != _BOOT_SIGS:
        STATE.loaded_sigs = None  # import 中に変更された: 最初の要求で再ロードさせる
    warm()
    for p in DEFAULT_RULE_FILES:  # プリロード(失敗しても起動する)
        try:
            guard_rules_file(str(p))
        except Exception:
            pass

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    old_umask = os.umask(0o177)
    try:
        srv.bind(sock_path)
    finally:
        os.umask(old_umask)
    os.chmod(sock_path, 0o600)
    my_ino = os.lstat(sock_path).st_ino
    srv.listen(64)

    def _stop(_s, _f):
        STATE.stop = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGALRM, _on_alarm)
    threading.Thread(target=_watchdog, daemon=True).start()
    try:
        event_loop(srv, sock_path)
    finally:
        srv.close()
        try:
            cur = os.lstat(sock_path)
            if cur.st_ino == my_ino:
                os.unlink(sock_path)
        except OSError:
            pass
        os.close(lock_fd)
    return 0


# --- クライアント側サブコマンド -----------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] not in ("--daemon", "--ping", "--status", "--stop", "--query"):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 64
    cmd = argv[0]
    if cmd == "--daemon":
        return run_daemon()
    timeout = decide.client_timeout()
    if cmd == "--ping":
        r = decide.daemon_call({"op": "ping"}, timeout)
        if r and r.get("ok") and r.get("pong"):
            print("pong")
            return 0
        return 1
    if cmd == "--status":
        r = decide.daemon_call({"op": "status"}, timeout)
        if r and r.get("ok"):
            print(json.dumps(r, sort_keys=True))
            return 0
        print("agent-decide: not running", file=sys.stderr)
        return 1
    if cmd == "--stop":
        r = decide.daemon_call({"op": "stop"}, timeout)
        if not (r and r.get("ok")):
            print("agent-decide: not running", file=sys.stderr)
            return 1
        path = decide.sock_path()
        for _ in range(40):
            if not os.path.exists(path):
                break
            time.sleep(0.05)
        return 0
    # --query
    try:
        req = json.loads(sys.stdin.read())
    except Exception:
        print("agent-decide: invalid request json", file=sys.stderr)
        return 64
    res = decide.query_daemon(req, timeout)
    if res is None:
        print("agent-decide: no usable daemon response", file=sys.stderr)
        return 3
    print(json.dumps(res))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
