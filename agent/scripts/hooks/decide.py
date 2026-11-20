#!/usr/bin/env python3
"""rule_engine.py を各ツールのシム(agent/hooks/{claude,agy}/*.sh・agent/hooks/omp/*.ts)から
呼び出すためのCLI/インプロセス共通エントリポイント。

stdinで正規化済みJSONを受け取り、stdoutへ正規化済みの決定JSONを1行で返す。exit codeは常に0
(判定結果はstdoutのJSONで表現し、シム側がツール固有のexit code/JSON形式へ変換する)。
Python製hookからは `dispatch(req)` を直接呼び出して同一判定をインプロセスで実行できる。

入力(stdinのJSON、"family"で分岐):
  security_shell:  {family, command, cwd, rules_file, resolve_command_target}
  security_write:  {family, file_path, cwd, home, rules_file}
  write_scope:     {family, file_path, cwd, home, rules_file}  (Tier B, fail-closed — 他familyと違いrules_file欠落時もblock)
  vald_law1:        {family, file_path, vald_rules_file}
  vald_law2:        {family, command, cwd, vald_rules_file, scope_mode, workspaces?}
  vald_law345:      {family, file_path, content, vald_rules_file, scope_mode, cwd?, workspaces?}

出力(stdoutのJSON、1行):
  {"decision": "allow"|"ask"|"block", "reason": "...", "matches": [...]}
  security_shell はtier別に "block_matches"/"ask_matches" のIDリストも含める(シム側が
  claudeの「block全件→ask全件」評価順序を再現できるようにするため)。

旧 memory_context family は Phase 1 で supermemory.sh とともに完全撤去済み(各ハーネスは
ネイティブメモリ / MEMORY.md 経由でコンテキストを読み込む)。
"""
from __future__ import annotations

import json
import os
import socket
import stat
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rule_engine as re_  # noqa: E402

# --- decide_daemon.py (Unix ソケット常駐デーモン) への fast path クライアント --------------
# 不変条件: デーモンの有無・故障・偽物で hook の判定(decision と reason)は変わらない。
#   * デーモンは要求ごとに fork した子プロセスで評価する。子はクライアントの cwd(os.getcwd())へ chdir し、
#     環境変数をクライアントの os.environ へ丸ごと置換してから decide.dispatch() を呼ぶ。つまり
#     cwd・環境・相対パス・`git -C` を呼び出しプロセスの文脈で in-process と同じに解決する。
#     deadline を超えた子は SIGKILL され、その結果は絶対に採用しない({"ok": false} -> in-process へ)。
#   * 子が再現できない要求(未知キー・非 str の値・/proc /dev/fd /dev/std* を指す/経由するパス文字列)は
#     デーモンへ送らず in-process dispatch() で評価する(_process_relative_path)。
#   * デーモン不在・無応答・不正応答・タイムアウト・身元/コード署名の不一致は全て in-process へ
#     フォールバックする(判定は必ず行う。エラーを allow に変換することはない)。
#   * 接続先が正規のデーモンであることを、要求を送る前に /proc で確認する(_identity_ok)。
# in-process(fail-open)との違い(意図した仕様 D2): デーモンは一度ロードに成功したルール JSON /
#   コードが後で壊れた(再ロード失敗)場合に decision "block" を返す(fail-closed)。in-process は壊れた
#   ルールファイルを読むと各 handler の既定(多くは allow=fail-open、write_scope のみ block)に従う。
#   デーモンの方が安全側に倒れる差で、壊れたルールを直せば(stat が変われば)自動復旧する。
#   一度も正常ロードしていないルール、およびデーモンを使わない場合は in-process と同一挙動。
# 限界(正直に): 同一 uid の攻撃者は自プロセスの argv(/proc/<pid>/cmdline)を書き換えられるため、
# cmdline/exe/cgroup 検査は「偶発的な偽物・古いデーモン・別 repo のデーモン」を弾くもので、
# 同一 uid の悪意あるプロセスに対する完全な防御ではない(同一 uid は hook 自身も改変できる信頼境界内)。
# クライアントが別 mount namespace(コンテナ等)から同じソケットへ繋ぐ構成は対象外。
# 既定ではデーモンを使わない(実測で CLI 直呼びより速くならなかった。`agent/scripts/bench/run-agent-bench.sh --hooks --quick`
# 2026-11-20: CLI 直呼び p50 30.4ms、デーモン経由 p50 34.0ms。常駐プロセス・身元検査・systemd unit の複雑さに見合う利益が無い)。
# AGENT_DECIDE_DAEMON=1 を明示した場合だけ fast path を試す。
# AGENT_DECIDE_NO_DAEMON=1 は AGENT_DECIDE_DAEMON=1 より優先する kill switch(子プロセスへそのまま継承される)。
# AGENT_DECIDE_ALLOW_UNMANAGED=1 は systemd 管理外(テスト・手動起動)のデーモンを許す(cgroup 検査のみ緩和)。
# AGENT_DECIDE_DAEMON_SCRIPT は期待する decide_daemon.py のパス(テスト用。通常は本ファイルと同じ dir)。
import hashlib  # noqa: E402
import re as _re_mod  # noqa: E402

MAX_REQ_BYTES = 4 * 1024 * 1024
MAX_RESP_BYTES = 8 * 1024 * 1024
DEFAULT_TIMEOUT_S = 1.0
_VALID_DECISIONS = ("allow", "ask", "block")
_HERE = Path(__file__).resolve().parent
CODE_FILES = ("rule_engine.py", "decide.py", "decide_daemon.py")
_STR_KEYS = {"family", "command", "cwd", "rules_file", "harness", "file_path", "home", "vald_rules_file",
             "scope_mode", "content"}
_PATH_KEYS = ("file_path", "cwd", "rules_file", "vald_rules_file", "home")
# 子プロセスが再現できない「呼び出しプロセス固有」のパス(fd 番号・他 pid・/proc 経由)。
_PROC_MARKERS = ("/proc/", "/dev/fd", "/dev/stdin", "/dev/stdout", "/dev/stderr")


def code_signature(directory: Path | None = None, frozen: dict | None = None) -> str:
    """rule_engine.py / decide.py / decide_daemon.py の内容ハッシュ(クライアントは常にディスクから計算)。
    frozen={name: sha256hex} を渡すと、そのファイルはディスクを読まずその値を使う(デーモンが
    decide_daemon.py の起動時ハッシュを固定するため。ディスク上で編集されると不一致になる)。"""
    d = directory or _HERE
    h = hashlib.sha256()
    for name in CODE_FILES:
        digest = (frozen or {}).get(name) or hashlib.sha256((d / name).read_bytes()).hexdigest()
        h.update(f"{name}:{digest}\n".encode())
    return h.hexdigest()


def sock_path() -> str:
    p = os.environ.get("AGENT_DECIDE_SOCK")
    if p:
        return p
    d = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/uid-{os.getuid()}"
    return os.path.join(d, "agent-decide.sock")


def client_timeout() -> float:
    try:
        ms = float(os.environ.get("AGENT_DECIDE_TIMEOUT_MS", ""))
        if ms > 0:
            return ms / 1000.0
    except ValueError:
        pass
    return DEFAULT_TIMEOUT_S


def _is_process_relative(p: str) -> bool:
    return p == "/proc" or p == "/dev/fd" or p.startswith(("/proc/", "/dev/fd/", "/dev/stdin", "/dev/stdout", "/dev/stderr"))


def _process_relative_path(p: str) -> bool:
    """p(相対なら現 cwd 基準)をシンボリックリンクを手で辿って解決し、途中で /proc /dev/fd /dev/std* へ
    入るなら True。realpath だと解決後に目印が消える(symlink -> /dev/fd/3 -> 実ファイル)ため手で辿る。"""
    if any(m in p for m in _PROC_MARKERS):
        return True
    try:
        cur = p if os.path.isabs(p) else os.path.join(os.getcwd(), p)
        stack = [x for x in cur.split("/") if x not in ("", ".")][::-1]
        resolved, links = "/", 0
        while stack:
            name = stack.pop()
            if name == "..":
                resolved = os.path.dirname(resolved)
                continue
            cand = os.path.join(resolved, name)
            if _is_process_relative(cand):
                return True
            if os.path.islink(cand):
                links += 1
                target = os.readlink(cand)
                if links > 40 or any(m in target for m in _PROC_MARKERS):
                    return True
                if os.path.isabs(target):
                    resolved = "/"
                stack.extend([x for x in target.split("/") if x not in ("", ".")][::-1])
            else:
                resolved = cand
        return False
    except Exception:
        return True


def daemon_eligible(req) -> bool:
    """子プロセスが「クライアントの cwd・環境を再現すれば」同一判定を返せる要求だけ True。"""
    if not isinstance(req, dict):
        return False
    for k, v in req.items():
        if k in _STR_KEYS:
            if not isinstance(v, str) or any(m in v for m in _PROC_MARKERS):
                return False
        elif k == "workspaces":
            if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
                return False
        elif k == "resolve_command_target":
            if not isinstance(v, bool):
                return False
        else:
            return False  # 未知のキーは同一性を保証できない
    if req.get("family") not in HANDLERS:
        return False
    for k in _PATH_KEYS:
        if k in req and _process_relative_path(req[k]):
            return False
    try:
        os.getcwd()
    except OSError:
        return False
    return True


def _sock_trusted(path: str) -> bool:
    """ソケットと親ディレクトリが自分所有・他者アクセス不可であること(squatting 対策)。"""
    me = os.getuid()
    st = os.lstat(path)
    if not stat.S_ISSOCK(st.st_mode) or st.st_uid != me or st.st_mode & 0o077:
        return False
    dst = os.lstat(os.path.dirname(path))
    return stat.S_ISDIR(dst.st_mode) and dst.st_uid == me and not dst.st_mode & 0o077


def _exe_is_python(exe_link: str) -> bool:
    return bool(_re_mod.fullmatch(r"python[0-9.]*", os.path.basename(exe_link)))


def _cmdline_is_daemon(cmdline: bytes, cwd: str, expected_script: str) -> bool:
    """argv が `python* -I [-opts] <expected decide_daemon.py> --daemon` であること(-I 必須)。

    -I(isolated)が無い起動は PYTHONPATH / sitecustomize / usercustomize を解釈するため、
    同 uid の drop-in で偽コードを正規の argv・cgroup 内に差し込める。よって -I を要求する。
    """
    args = [a.decode("utf-8", "surrogateescape") for a in cmdline.split(b"\0") if a != b""]
    if len(args) < 3:
        return False
    rest = args[1:]
    i = 0
    isolated = False
    # 許可リスト方式: -I -B -E -s -S -u -O -q とその結合形(-IB 等)だけ。-c/-m を含む結合形(-Ic 等)・
    # -X/-W/-x/-R 等のオプション、"--"、"-" は全て拒否する。
    while i < len(rest) and rest[i].startswith("-"):
        if not _re_mod.fullmatch(r"-[IBEsSuOq]+", rest[i]):
            return False
        isolated = isolated or "I" in rest[i]
        i += 1
    if not isolated or i >= len(rest) or rest[i] == "-":
        return False
    script = os.path.realpath(os.path.join(cwd, rest[i]))
    return script == expected_script and rest[i + 1:] == ["--daemon"]


def _environ_is_clean(raw: bytes) -> bool:
    """/proc/<pid>/environ に PYTHON* / LD_* が無いこと(-I でも LD_PRELOAD 等は効くため環境ごと見る)。"""
    for ent in raw.split(b"\0"):
        name = ent.split(b"=", 1)[0]
        if name.startswith(b"PYTHON") or name.startswith(b"LD_"):
            return False
    return True


def _cgroup_is_managed(text: str) -> bool:
    for line in text.splitlines():
        if "agent-decide.service" in line.rsplit(":", 1)[-1].split("/"):
            return True
    return False


def _identity_ok(pid: int) -> bool:
    """SO_PEERCRED の pid が、期待する decide_daemon.py を python で実行している正規のデーモンか。"""
    try:
        proc = f"/proc/{int(pid)}"
        if not _exe_is_python(os.readlink(f"{proc}/exe")):
            return False
        expected = os.path.realpath(os.environ.get("AGENT_DECIDE_DAEMON_SCRIPT") or str(_HERE / "decide_daemon.py"))
        with open(f"{proc}/cmdline", "rb") as f:
            cmdline = f.read(65536)
        if not _cmdline_is_daemon(cmdline, os.readlink(f"{proc}/cwd"), expected):
            return False
        # 同 uid なら読める。読めない/失敗は except で False(=in-process へフォールバック)。
        with open(f"{proc}/environ", "rb") as f:
            if not _environ_is_clean(f.read(1 << 20)):
                return False
        if not os.environ.get("AGENT_DECIDE_ALLOW_UNMANAGED"):
            with open(f"{proc}/cgroup") as f:
                if not _cgroup_is_managed(f.read(65536)):
                    return False
        return True
    except Exception:
        return False


def daemon_call(msg: dict, timeout: float):
    """1 往復の JSON 通信。失敗・身元不一致は全て None(呼び出し側がフォールバックする)。"""
    path = sock_path()
    try:
        if not _sock_trusted(path):
            return None
        payload = (json.dumps(msg) + "\n").encode("utf-8")
        if len(payload) > MAX_REQ_BYTES:
            return None
        deadline = time.monotonic() + timeout
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.settimeout(timeout)
            s.connect(path)
            cred = s.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
            pid, uid, _gid = struct.unpack("3i", cred)
            if uid != os.getuid() or not _identity_ok(pid):
                return None  # 要求を送る前に棄却する(要求内容を偽物へ渡さない)
            s.sendall(payload)
            buf = bytearray()
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None
                s.settimeout(remaining)
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
                if len(buf) > MAX_RESP_BYTES:
                    return None
                if buf.endswith(b"\n"):
                    break
        finally:
            s.close()
        resp = json.loads(bytes(buf).decode("utf-8"))
        return resp if isinstance(resp, dict) else None
    except Exception:
        return None


def query_daemon(req: dict, timeout: float | None = None):
    """デーモンの判定結果 dict、または使えない場合 None(呼び出し側がインプロセスへ落とす)。"""
    if not daemon_eligible(req):
        return None
    try:
        msg = {"op": "decide", "req": req, "env": dict(os.environ), "cwd": os.getcwd()}
    except OSError:
        return None
    resp = daemon_call(msg, timeout if timeout is not None else client_timeout())
    if not resp or resp.get("ok") is not True:
        return None
    try:
        if resp.get("sig") != code_signature():
            return None  # 古い/別のコードのデーモンの応答は採用しない
    except Exception:
        return None
    result = resp.get("result")
    if not isinstance(result, dict) or result.get("decision") not in _VALID_DECISIONS:
        return None
    return result


def _load_json(path: str):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _res(decision: str, reason: str = "", **extra) -> dict:
    payload = {"decision": decision, "reason": reason}
    payload.update(extra)
    return payload


def handle_security_shell(req: dict) -> dict:
    rules_data = _load_json(req["rules_file"])
    if not rules_data:
        return _res("allow", "rules file missing/invalid (fail-open)")
    command = req.get("command", "")
    cwd = req.get("cwd", ".")
    resolve_target = req.get("resolve_command_target", True)
    harness = req.get("harness")
    all_rules = rules_data.get("shell_command_rules", [])

    # all_matches: JSON宣言順のまま全一致ルールを返す(pi実装が「宣言順に1パスで走査し、
    # hasUI時はマッチ毎にconfirmを出し承認後も走査継続する」挙動を再現するために必要
    # — claude/agyはこのフィールドを使わずtop-levelのdecision/reasonのみ参照する)。
    # tier/descriptionをここで直接埋め込む(呼び出し側にモジュールロード時キャッシュ等の
    # 別経路でルール定義を再取得させない設計 — security-audit指摘2026-09-03: 呼び出し側が
    # idだけを受け取り自前の陳腐化しうるキャッシュから逆引きすると、decide.pyがフレッシュに
    # 読んだルールファイルとキャッシュがズレた場合にマッチが未確認のまま握り潰される穴になる。
    # decide.py自身が"今読んだばかりの"rules_dataから直接tier/descriptionを渡すことで、
    # 呼び出し側がローカルキャッシュを持つ必要そのものを無くす)。
    all_matches = [
        {"id": r.get("id"), "tier": r.get("tier"), "description": r.get("description")}
        for r in all_rules
        if re_.evaluate_rule(r, command, cwd, resolve_command_target=resolve_target)
    ]

    # top-level decision: block全件→ask全件の2パス評価(claude/agyの historical な優先順位、
    # ask()がexit 0で即終了するため先に評価すると複合コマンドで後続のblock条件に到達できない
    # 罠への対策)。
    block_rules = [r for r in all_rules if r.get("tier") == "block"]
    ask_rules = [r for r in all_rules if r.get("tier") == "ask"]
    decision = "allow"
    reason = ""
    matched_rule_id = None
    for rule in block_rules:
        if re_.evaluate_rule(rule, command, cwd, resolve_command_target=resolve_target):
            decision, reason, matched_rule_id = "block", rule.get("description", ""), rule.get("id")
            break
    if decision != "block":
        for rule in ask_rules:
            if re_.evaluate_rule(rule, command, cwd, resolve_command_target=resolve_target):
                decision, reason, matched_rule_id = "ask", rule.get("description", ""), rule.get("id")
                break

    extra = {"all_matches": all_matches}
    if matched_rule_id is not None:
        extra["matched_rule_id"] = matched_rule_id
    return _res(decision, reason, **extra)


def handle_security_write(req: dict) -> dict:
    rules_data = _load_json(req["rules_file"])
    if not rules_data:
        return _res("allow", "rules file missing/invalid (fail-open)")
    candidates = re_.resolve_write_path_candidates(
        req.get("file_path", ""), req.get("cwd", "."), req.get("home", "")
    )
    hit = re_.eval_sensitive_write_path(rules_data.get("sensitive_write_path_rules", []), candidates)
    if hit:
        rule_id, label = hit
        return _res("block", label, matched_rule_id=rule_id, resolved_path=candidates[2])
    return _res("allow")


def handle_write_scope(req: dict) -> dict:
    """Tier B 書込保護ゲート。他family(handle_security_write等)はrules_file欠落時
    "allow"(fail-open)を返すが、write_scope は swarm-implement/hooks/skills/SWARM.md/
    settings.json等の自己言及的な保護対象(swarmの行動規範そのもの)を扱うため、判定不能な状態を
    安全側ではなく危険側の緩さとみなし、明示的にblockする(fail-closed)。これは意図的な非対称
    設計であり、他familyのfail-open方針とは異なる(agent/write-scope-rules.jsonが読めない/壊れて
    いる状態でTier B保護対象への書込を素通りさせないため)。"""
    rules_data = _load_json(req["rules_file"])
    # fail-closed: 欠落/構文エラー(None)だけでなく、構文的に有効でも期待する構造
    # (dict かつ suffix_patterns / fixed_absolute_path_patterns の両キーを持つ)を欠く場合も
    # blockする。これを怠ると rules_data が truthy な dict (例 {"unrelated_key":123}) や
    # list ([1,2,3]) の場合に eval_write_scope が空リストへフォールバックして常にallowを返し、
    # Tier B保護対象書込がfail-openですり抜ける(かつ write-scope-rules.json 自身は保護対象外
    # なので、これを壊れた有効JSONへ書き換えると以降全ての保護がすり抜ける連鎖が成立する)。
    # また list型を eval_write_scope の rules.get に渡すと AttributeError で非ゼロ終了し decide.py の
    # 「exit code は常に0」契約にも違反するため、ここで型・構造を先に検証する。
    if (
        not isinstance(rules_data, dict)
        or not isinstance(rules_data.get("suffix_patterns"), list)
        or not isinstance(rules_data.get("fixed_absolute_path_patterns"), list)
    ):
        # キー存在だけでなく値がlistであることまで検証する(Checker advisory 2026-09-07):
        # 例 {"suffix_patterns":"x", ...} のように値が文字列だと、キー存在検査は通過し
        # rule_engine 側の `rules.get(...) or []` が文字列を返して文字単位でglob評価され、
        # 実質パターン失効=fail-openになる(保護対象パスがすり抜ける)。write_scope は
        # Tier B で fail-open 禁止のため、型不一致も malformed とみなし block へ倒す。
        return _res("block", "write-scope rules malformed; failing closed")
    candidates = re_.resolve_write_path_candidates(
        req.get("file_path", ""), req.get("cwd", "."), req.get("home", "")
    )
    realpath = candidates[-1]  # canonical (os.path.realpath 済み)
    if re_.eval_write_scope(rules_data, realpath, req.get("home", "")):
        return _res("block", "Tier B protected path (write-scope)", resolved_path=realpath)
    return _res("allow")


def handle_vald_law1(req: dict) -> dict:
    vald_rules = _load_json(req["vald_rules_file"])
    if not vald_rules:
        return _res("allow", "vald rules file missing/invalid (fail-open)")
    msg = re_.eval_vald_law1(vald_rules, req.get("file_path", ""))
    if msg:
        return _res("block", msg, matched_rule_id="law1")
    return _res("allow")


def handle_vald_law2(req: dict) -> dict:
    vald_rules = _load_json(req["vald_rules_file"])
    if not vald_rules:
        return _res("allow", "vald rules file missing/invalid (fail-open)")
    hit = re_.eval_vald_law2(
        vald_rules,
        req.get("command", ""),
        req.get("cwd", "."),
        req.get("scope_mode", "none"),
        workspaces=req.get("workspaces"),
    )
    if hit:
        rule_id, remediation = hit
        return _res("block", f"Vald Law 2 violation: {remediation}", matched_rule_id=rule_id)
    return _res("allow")


def handle_vald_law345(req: dict) -> dict:
    vald_rules = _load_json(req["vald_rules_file"])
    if not vald_rules:
        return _res("allow", "vald rules file missing/invalid (fail-open)")
    scope_mode = req.get("scope_mode", "none")
    if scope_mode == "none":
        is_vald_scope = True
    else:
        pattern = vald_rules.get("vald_repo_pattern", "")
        import re as _re
        candidates = [req.get("cwd", ""), req.get("file_path", "")] + list(req.get("workspaces") or [])
        is_vald_scope = any(_re.search(pattern, c, _re.IGNORECASE) for c in candidates if c)
    violations = re_.eval_vald_law345(
        vald_rules, req.get("file_path", ""), req.get("content", ""), is_vald_scope
    )
    if violations:
        return _res("ask", "", violations=violations)
    return _res("allow")


HANDLERS = {
    "security_shell": handle_security_shell,
    "security_write": handle_security_write,
    "write_scope": handle_write_scope,
    "vald_law1": handle_vald_law1,
    "vald_law2": handle_vald_law2,
    "vald_law345": handle_vald_law345,
}


def dispatch(req: dict) -> dict:
    if not isinstance(req, dict):
        return _res("allow", "invalid input JSON (fail-open)")
    family = req.get("family")
    handler = HANDLERS.get(family)
    if not handler:
        return _res("allow", f"unknown family: {family} (fail-open)")
    return handler(req)


def dispatch_fast(req) -> dict:
    """デーモン経由 → 不可ならインプロセス dispatch()。結果は同一入力に対し同一。"""
    if isinstance(req, dict) and os.environ.get("AGENT_DECIDE_DAEMON") == "1" and not os.environ.get("AGENT_DECIDE_NO_DAEMON"):
        res = query_daemon(req)
        if res is not None:
            return res
    return dispatch(req)


def main():
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except Exception:
        req = None
    res = _res("allow", "invalid input JSON (fail-open)") if req is None else dispatch_fast(req)
    print(json.dumps(res))
    sys.exit(0)


if __name__ == "__main__":
    main()
