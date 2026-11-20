#!/usr/bin/env bash
# agent/scripts/hooks/decide_daemon.py (Unix ソケット常駐デーモン) と decide.py の fast path を
# 実プロセスを起動して検証する。最重要の不変条件: デーモンの有無・故障・偽物で hook の判定
# (decision と reason)が変わらないこと。
#   - 同一入力表(相対パス・cwd/env 依存・GIT_DIR を含む)で、インプロセス / NO_DAEMON /
#     デーモン直接(--query) / decide.py(fast path) の出力と rc が一致(不適格な要求はデーモンへ送られない)
#   - デーモンの cwd・GIT_* 環境がクライアントと違っても判定が変わらない
#   - ルール JSON・コードの変更検知 (mtime+ctime+size)、再ロード失敗時の fail-closed(block)
#   - 偽のリスナー・古いコード署名・cgroup/cmdline 不一致のデーモンの応答を採用しない
#   - 権限 (0700/0600)、SO_PEERCRED、サイズ上限、JSON のみ、多重起動、stale ソケット掃除
#   - 非 str の rules_file・FIFO・無言クライアントでデーモンが落ちない/詰まらない
#   - フォールバック、--ping/--status/--stop(他プロセスを止めない)、bun からの callDecide
# 一時物は全て mktemp -d 配下(実 $XDG_RUNTIME_DIR のソケットには触れない)。起動した子プロセスは
# /proc/<pid>/cmdline を確認してから kill し、終了時に残っていないことを検査する。
#
# usage: agent/scripts/test-decide-daemon.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS="$ROOT/agent/scripts/hooks"
DECIDE="$HOOKS/decide.py"
DAEMON="$HOOKS/decide_daemon.py"
PY=(python3 -I -B)

T="$(mktemp -d)"
chmod 700 "$T"
OTHER_CWD="$T/othercwd"; mkdir -p "$OTHER_CWD"
SPAWNED=()      # 自分が起動した daemon / 偽リスナーの pid
DECOY_PID=""

# cmdline に <pattern> を含む自分の子だけを kill する(pid 再利用で他人を kill しない)。
safe_kill() { # <pid> <pattern> [signal]
    local p="$1" pat="$2" sig="${3:-TERM}"
    [[ -n "$p" && -r "/proc/$p/cmdline" ]] || return 0
    if tr '\0' ' ' <"/proc/$p/cmdline" | grep -q -- "$pat"; then kill -"$sig" "$p" 2>/dev/null; fi
    return 0
}
cleanup() {
    local p
    for p in "${SPAWNED[@]:-}"; do safe_kill "$p" "decide_daemon.py\|FAKE_LISTENER_T8\|fake_daemon.py" KILL; done
    [[ -n "$DECOY_PID" ]] && safe_kill "$DECOY_PID" "sleep" KILL
    wait 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT
export AGENT_DECIDE_SOCK="$T/d.sock"
export AGENT_DECIDE_ALLOW_UNMANAGED=1   # テストのデーモンは systemd 管理外(cgroup 検査のみ緩和)
export AGENT_DECIDE_DAEMON=1            # fast path は opt-in(既定 off)。このテストはデーモン経路を検証するので明示する
unset AGENT_DECIDE_NO_DAEMON AGENT_DECIDE_TIMEOUT_MS AGENT_DECIDE_DAEMON_SCRIPT
while IFS= read -r v; do [[ -n "$v" ]] && unset "$v"; done < <(compgen -e | grep '^GIT_' || true)

total_fail=0
ok() { echo "[OK] $1"; }
ng() { echo "[FAIL] $1"; total_fail=$((total_fail + 1)); }
check() { # <desc> <expected> <got>
    if [[ "$2" == "$3" ]]; then ok "$1"; else ng "$1 : expected=[$2] got=[$3]"; fi
}
section() { echo; echo "=== $1 ==="; }
jget() { "${PY[@]}" -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(str(v).lower() if isinstance(v,bool) else v)' "$1"; }

# デーモンは常にクライアントと異なる cwd から起動する(cwd 依存の取りこぼしを検出するため)。
DPY=("${PY[@]}")   # デーモン側の python 起動形(身元検査テストで -I 無し等へ一時的に差し替える)
# 正規のデーモンは PYTHON* / LD_* を環境に持たない(decide.py が環境ごと検査する)。開発シェルが
# 持つ値(LD_LIBRARY_PATH 等)は起動時に外す。意図して持たせるケースは引数の env 代入で再指定する。
scrub_args() { local n; while IFS= read -r n; do printf -- '-u\n%s\n' "$n"; done < <(compgen -e | grep -E '^(PYTHON|LD_)' || true); }
start_daemon() { # [daemon script path] [env assignments...] -> DPID
    local script="${1:-$DAEMON}"; shift || true
    local -a scrub; mapfile -t scrub < <(scrub_args)
    ( cd "$OTHER_CWD" && exec env "${scrub[@]}" "$@" "${DPY[@]}" "$script" --daemon >"$T/daemon.log" 2>&1 ) &
    DPID=$!
    SPAWNED+=("$DPID")
    local i
    for i in $(seq 1 100); do
        AGENT_DECIDE_DAEMON_SCRIPT="$script" "${PY[@]}" "$script" --ping >/dev/null 2>&1 && return 0
        sleep 0.05
    done
    return 1
}
stop_daemon() { # [daemon script path]
    local script="${1:-$DAEMON}" i
    AGENT_DECIDE_DAEMON_SCRIPT="$script" "${PY[@]}" "$script" --stop >/dev/null 2>&1
    for i in $(seq 1 40); do kill -0 "$DPID" 2>/dev/null || break; sleep 0.1; done
    safe_kill "$DPID" "decide_daemon.py" KILL   # --stop が効かなくてもテストをハングさせない
    wait "$DPID" 2>/dev/null
}
decide_cli() { printf '%s' "$1" | "${PY[@]}" "$DECIDE"; }
decide_inproc() { printf '%s' "$1" | AGENT_DECIDE_NO_DAEMON=1 "${PY[@]}" "$DECIDE"; }
decision_of() { "${PY[@]}" -c 'import json,sys; print(json.load(sys.stdin)["decision"])'; }
req_count() { "${PY[@]}" "$DAEMON" --status | jget requests; }

# 生ソケットクライアント(身元検証なし): デーモン側の挙動だけを見る。
cat >"$T/rawclient.py" <<'PYEOF'
import json, os, socket, sys, time
sys.path.insert(0, sys.argv[1])
import decide
mode = sys.argv[2]
s = socket.socket(socket.AF_UNIX); s.settimeout(15); s.connect(os.environ["AGENT_DECIDE_SOCK"])
if mode == "bytes":
    payload = eval(sys.argv[3])
else:  # decide <req json> : op=decide + 自プロセスの env / cwd
    payload = (json.dumps({"op": "decide", "req": json.loads(sys.argv[3]), "env": dict(os.environ), "cwd": os.getcwd()}) + "\n").encode()
try:
    s.sendall(payload)
except OSError:
    pass
buf = b""
try:
    while not buf.endswith(b"\n"):
        c = s.recv(65536)
        if not c:
            break
        buf += c
except OSError:
    pass
print(buf.decode("utf-8", "replace").strip())
PYEOF
raw() { "${PY[@]}" "$T/rawclient.py" "$HOOKS" bytes "$1"; }
rawdecide() { "${PY[@]}" "$T/rawclient.py" "$HOOKS" decide "$1"; }

MAIN_CWD="$T/mainrepo"
mkdir -p "$MAIN_CWD"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$MAIN_CWD" init -q -b main
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$MAIN_CWD" -c user.name=t -c user.email=t@example.invalid \
    -c commit.gpgsign=false commit -q --allow-empty -m init

SEC="$ROOT/agent/security-rules.json"
VALD="$ROOT/agent/vald-law-rules.json"
WS="$ROOT/agent/write-scope-rules.json"

# ------------------------------------------------------------------
section "起動・権限・ping/status"
# ------------------------------------------------------------------
if start_daemon; then ok "daemon starts and answers ping"; else ng "daemon failed to start (or its identity/socket is not trusted): $(cat "$T/daemon.log")"; echo "$total_fail FAILED (aborting: daemon prerequisite)"; exit 1; fi
check "socket mode 0600" "600" "$(stat -c %a "$AGENT_DECIDE_SOCK")"
check "socket owned by me" "$(id -u)" "$(stat -c %u "$AGENT_DECIDE_SOCK")"
check "--ping prints pong" "pong" "$("${PY[@]}" "$DAEMON" --ping)"
status="$("${PY[@]}" "$DAEMON" --status)"
check "--status reports own pid" "$DPID" "$(printf '%s' "$status" | jget pid)"
check "--status reports own uid" "$(id -u)" "$(printf '%s' "$status" | jget uid)"
check "daemon cwd is / (independent of launch dir; status cwd)" "/" "$(printf '%s' "$status" | jget cwd)"

# ------------------------------------------------------------------
section "判定の同一性 (in-process / NO_DAEMON / --query / decide.py fast path)"
# ------------------------------------------------------------------
FAKEBIN="$T/fakebin"; mkdir -p "$FAKEBIN"
# 遅い git(1.0 秒。rule_engine は 1 要求で git を複数回呼ぶ)。出力するブランチ名は env FAKE_BRANCH で決まる(= クライアントの env を再現しないと判定が変わる)
printf '%s\n' '#!/bin/sh' 'sleep 1.0' 'echo "${FAKE_BRANCH:-feature}"' >"$FAKEBIN/git"; chmod +x "$FAKEBIN/git"
FD3FILE="$ROOT/agent/SWARM.md"   # クライアントだけが fd 3 にこれを開く(デーモン/子の fd 3 とは別物)
mkdir -p "$T/links/deep/er"
ln -s /proc/self/cwd "$T/links/proccwd"
ln -s /dev/fd/3 "$T/links/fd3"
ln -s "$T/links/fd3" "$T/links/chain"
ln -s ../../../../../../../../../../../../../../../../proc/self/cwd "$T/links/deep/er/relproc"
BIGRULES="$T/bigrules.json"
"${PY[@]}" -c 'import sys; sys.stdout.write("{\"shell_command_rules\":[{\"id\":\"big\",\"tier\":\"block\",\"description\":\"big\",\"all_of\":[\"\\\\bfoo-big\\\\b\"]}],\"sensitive_write_path_rules\":[],\"pad\":\"" + "A"*(5*1024*1024) + "\"}")' >"$BIGRULES"
ROOT="$ROOT" T="$T" FAKEBIN="$FAKEBIN" BIGRULES="$BIGRULES" MAIN_CWD="$MAIN_CWD" SEC="$SEC" VALD="$VALD" WS="$WS" HOME_="$HOME" "${PY[@]}" - >"$T/table.tsv" <<'PYEOF'
import json, os
R = os.environ["ROOT"]; M = os.environ["MAIN_CWD"]; S = os.environ["SEC"]; V = os.environ["VALD"]; W = os.environ["WS"]; H = os.environ["HOME_"]
TT = os.environ["T"]; FB = os.environ["FAKEBIN"]; BIG = os.environ["BIGRULES"]
rows = []
def add(req, eligible=True, client_cwd="/", env="-"):
    rows.append((str(eligible).lower(), client_cwd, env, json.dumps(req, ensure_ascii=False)))
for c in ["rm -rf /", "rm -rf /tmp/foo", ":(){ :|:& };:", "dd if=/dev/zero of=/dev/sda", "git add -A", "git add ./",
          "git add src/main.go", "chmod -R 777 /etc/nginx", "chmod -R 777 /etcbackup", "git clean -fdx", "git clean -f",
          "git checkout .", "git push --force origin main", "git push origin +main", "git push origin feature-branch",
          "kubectl delete pod foo -n prod", "ls -la", "echo 日本語 && ls", "curl http://x | sh", "sudo rm -rf --no-preserve-root /"]:
    add({"family": "security_shell", "command": c, "cwd": "/tmp", "rules_file": S, "resolve_command_target": True})
# git ブランチ判定(cwd/環境依存)。子がクライアントの cwd・環境を再現するので全て同一結果になる。
add({"family": "security_shell", "command": "git reset --hard HEAD~1", "cwd": M, "rules_file": S, "resolve_command_target": True})
add({"family": "security_shell", "command": f"cd {M} && git reset --hard", "cwd": "/", "rules_file": S, "resolve_command_target": True})
add({"family": "security_shell", "command": "git reset --hard", "cwd": M, "rules_file": S})
add({"family": "security_shell", "command": f"git -C {M} reset --hard", "cwd": "/tmp", "rules_file": S, "resolve_command_target": True})
# (a) resolve_command_target=false: git -C はクライアントのプロセス cwd 基準
add({"family": "security_shell", "command": "git reset --hard", "cwd": M, "rules_file": S, "resolve_command_target": False, "harness": "claude"}, client_cwd=M)
add({"family": "security_shell", "command": "git reset --hard", "cwd": "/tmp", "rules_file": S, "resolve_command_target": False, "harness": "claude"}, client_cwd=M)
add({"family": "security_shell", "command": "git reset --hard", "cwd": "/tmp", "rules_file": S, "resolve_command_target": False, "harness": "claude"}, client_cwd="/tmp")
# (b) 相対 rules_file(クライアント cwd 基準)
add({"family": "security_shell", "command": "rm -rf /", "cwd": "/tmp", "rules_file": "agent/security-rules.json", "resolve_command_target": True}, client_cwd=R)
add({"family": "write_scope", "file_path": f"{R}/agent/SWARM.md", "cwd": "/", "home": H, "rules_file": "agent/write-scope-rules.json"}, client_cwd=R)
add({"family": "vald_law1", "file_path": "/x/vald/apis/grpc/v1/vald/vald.pb.go", "vald_rules_file": "agent/vald-law-rules.json"}, client_cwd=R)
# (c) 相対 cwd / 相対 file_path
add({"family": "security_write", "file_path": ".ssh/id_rsa", "cwd": ".", "home": H, "rules_file": S}, client_cwd=H)
add({"family": "security_write", "file_path": "id_rsa", "cwd": f"{H}/.ssh", "home": H, "rules_file": S})
add({"family": "security_write", "file_path": "../.ssh/id_rsa", "cwd": "/tmp", "home": H, "rules_file": S})
add({"family": "write_scope", "file_path": "agent/SWARM.md", "cwd": ".", "home": H, "rules_file": W}, client_cwd=R)
add({"family": "vald_law2", "command": "go get x", "cwd": ".", "vald_rules_file": V, "scope_mode": "cwd_and_resolved_path"}, client_cwd="/tmp")
# (d) クライアントの環境にだけある変数(GIT_* / PATH / 任意)。環境は子へ丸ごと再現される。
for e in ["GIT_DIR=/nonexistent-git-dir", f"GIT_WORK_TREE={M}", "GIT_CONFIG_COUNT=1", "GIT_CEILING_DIRECTORIES=/",
          "GIT_OBJECT_DIRECTORY=/nonexistent", "GIT_INDEX_FILE=/nonexistent", "GIT_TRACE=1", "GIT_AUTHOR_NAME=someone", "GIT_EDITOR=true"]:
    add({"family": "security_shell", "command": "git reset --hard", "cwd": M, "rules_file": S, "resolve_command_target": True}, env=e)
# 遅い git(1.0 秒。rule_engine は 1 要求で git を複数回呼ぶ): クライアントの PATH と FAKE_BRANCH を再現しないと判定が変わる(block <-> allow)。遅くても結果は同一。
for br, ac in [("main", "block"), ("feature", "allow")]:
    add({"family": "security_shell", "command": "git reset --hard", "cwd": M, "rules_file": S, "resolve_command_target": True},
        env=f"PATH={FB}:/usr/bin:/bin FAKE_BRANCH={br} AGENT_DECIDE_TIMEOUT_MS=6000")
# 4MiB 超 / 通常ファイルでない rules_file は in-process と同じ読み込みで評価される
add({"family": "security_shell", "command": "foo-big x", "cwd": "/tmp", "rules_file": BIG, "resolve_command_target": True})
add({"family": "security_shell", "command": "rm -rf /", "cwd": "/tmp", "rules_file": "/dev/null", "resolve_command_target": True})
# 子が再現できない呼び出しプロセス固有のパス(/proc 経由・fd 番号・それらへの symlink)はデーモンへ送らない
for fp in ["/proc/self/cwd/agent/SWARM.md", "/proc/thread-self/cwd/agent/SWARM.md", "/dev/fd/3", f"{TT}/links/proccwd/agent/SWARM.md",
           f"{TT}/links/fd3", f"{TT}/links/chain", f"{TT}/links/deep/er/relproc/agent/SWARM.md"]:
    add({"family": "write_scope", "file_path": fp, "cwd": "/", "home": H, "rules_file": W}, eligible=False, client_cwd=R)
# command 文字列が呼び出しプロセスの fd(/dev/fd/4 = クライアントだけが開いた main ブランチの repo)を指す
add({"family": "security_shell", "command": "git -C /dev/fd/4 reset --hard", "cwd": "/tmp", "rules_file": S, "resolve_command_target": True}, eligible=False)
# 未知キー・非 str の値はデーモンへ送らない
add({"family": "security_shell", "command": "rm -rf /", "cwd": "/tmp", "rules_file": S, "resolve_command_target": True, "extra": 1}, eligible=False)
add({"family": "security_shell", "command": "rm -rf /", "cwd": "/tmp", "rules_file": S, "resolve_command_target": True, "harness": 5}, eligible=False)
add({"family": "nonexistent_family"}, eligible=False)
for p in [f"{H}/.ssh/id_rsa", f"{H}/.aws/credentials", "/etc/shadow", "/tmp/ok.txt", f"{R}/README.md", ".env", f"{H}/.gnupg/x"]:
    add({"family": "security_write", "file_path": p, "cwd": "/tmp", "home": H, "rules_file": S})
for p in [f"{R}/agent/skills/x/SKILL.md", f"{R}/agent/agents/a.md", f"{R}/agent/hooks/claude/x.sh", "/tmp/foo.txt", f"{R}/README.md",
          f"{H}/.claude/settings.json", f"{R}/agent/SWARM.md"]:
    add({"family": "write_scope", "file_path": p, "cwd": "/", "home": H, "rules_file": W})
for p in ["/x/vald/apis/grpc/v1/vald/vald.pb.go", "/x/vald/internal/foo.go", "/x/other/a.pb.go"]:
    add({"family": "vald_law1", "file_path": p, "vald_rules_file": V})
for c in ["go get github.com/foo/bar", "go mod tidy", "ls", "make proto/all"]:
    add({"family": "vald_law2", "command": c, "cwd": "/x/vald", "vald_rules_file": V, "scope_mode": "none"})
    add({"family": "vald_law2", "command": c, "cwd": "/x/vald", "vald_rules_file": V, "scope_mode": "cwd_and_resolved_path", "workspaces": ["/w"]})
for content in ["errors.New(\"x\")", "panic(\"x\")", "log.Fatal(\"x\")", "package a\n", "fmt.Errorf(\"x\")"]:
    add({"family": "vald_law345", "file_path": "/x/vald/internal/a.go", "content": content, "vald_rules_file": V, "scope_mode": "none"})
    add({"family": "vald_law345", "file_path": "/x/other/a.go", "content": content, "vald_rules_file": V, "scope_mode": "cwd_and_resolved_path", "cwd": "/x/other"})
add({"family": "security_shell", "command": "rm -rf /", "cwd": "/tmp", "rules_file": "/nonexistent/rules.json", "resolve_command_target": True})
add({"family": "write_scope", "file_path": "/tmp/a", "cwd": "/", "home": H, "rules_file": "/nonexistent/ws.json"})
for r in rows:
    print("\t".join(r))
PYEOF
n=0; elig=0; mism=0; declare -A seen
run_path() { # <client_cwd> <env words> <mode> <json>  -> "<stdout>|rc=<rc>"。クライアントだけが fd 3 に FD3FILE を開く
    local cc="$1" envs="$2" mode="$3" js="$4" out rc
    local -a pre=(env)
    [[ "$envs" != "-" ]] && pre+=($envs)
    case "$mode" in
        inproc) pre+=(AGENT_DECIDE_NO_DAEMON=1); out="$(cd "$cc" && printf '%s' "$js" | "${pre[@]}" "${PY[@]}" "$DECIDE" 3<"$FD3FILE" 4<"$MAIN_CWD" 2>/dev/null)"; rc=$? ;;
        query)  out="$(cd "$cc" && printf '%s' "$js" | "${pre[@]}" "${PY[@]}" "$DAEMON" --query 3<"$FD3FILE" 4<"$MAIN_CWD" 2>/dev/null)"; rc=$? ;;
        cli)    out="$(cd "$cc" && printf '%s' "$js" | "${pre[@]}" "${PY[@]}" "$DECIDE" 3<"$FD3FILE" 4<"$MAIN_CWD" 2>/dev/null)"; rc=$? ;;
    esac
    printf '%s|rc=%s' "$out" "$rc"
}
before_req="$(req_count)"
while IFS=$'\t' read -r eligible cc envs js; do
    n=$((n + 1))
    a="$(run_path "$cc" "$envs" inproc "$js")"
    b="$(run_path "$cc" "$envs" query "$js")"
    c="$(run_path "$cc" "$envs" cli "$js")"
    seen[$(printf '%s' "${a%|rc=*}" | decision_of)]=1
    bad=0
    [[ "$a" == "$c" ]] || bad=1
    if [[ "$eligible" == "true" ]]; then elig=$((elig + 1)); [[ "$a" == "$b" ]] || bad=1
    else [[ "$b" == "|rc=3" ]] || bad=1; fi
    if [[ "$bad" -eq 1 ]]; then
        mism=$((mism + 1))
        echo "[MISMATCH eligible=$eligible cwd=$cc env=$envs] $js"; echo "  inproc: $a"; echo "  query : $b"; echo "  cli   : $c"
    fi
done <"$T/table.tsv"
after_req="$(req_count)"
check "all $n table rows consistent across paths (mismatches)" "0" "$mism"
check "only eligible requests reach the daemon: --query+cli = 2x$elig, +1 status" "$((before_req + 2 * elig + 1))" "$after_req"
check "table covers allow/ask/block" "allow ask block" "$(printf '%s\n' "${!seen[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
REQ_RESET="$("${PY[@]}" -c 'import json,sys; print(json.dumps({"family":"security_shell","command":"git reset --hard","cwd":sys.argv[1],"rules_file":sys.argv[2],"resolve_command_target":True}))' "$MAIN_CWD" "$SEC")"
check "no child processes left under the daemon after the table (no zombies/orphans)" "" "$(pgrep -P "$DPID" | tr '\n' ' ' | sed 's/ $//')"
check "git reset --hard on main via daemon (daemon cwd=/): block" "block" "$(decide_cli "$REQ_RESET" | decision_of)"

# ------------------------------------------------------------------
section "デーモン環境の差 (子プロセスがクライアントの env/cwd を再現する)"
# ------------------------------------------------------------------
stop_daemon
start_daemon "$DAEMON" GIT_DIR=/nonexistent-git-dir GIT_WORK_TREE=/nonexistent || ng "daemon with GIT_DIR env failed to start"
c0="$(req_count)"
check "daemon started with GIT_DIR in ITS OWN env still decides like in-process (reset --hard on main)" "$(decide_inproc "$REQ_RESET" | decision_of)" "$(decide_cli "$REQ_RESET" | decision_of)"
check "  (and it was served by the daemon)" "$((c0 + 2))" "$(req_count)"
resp="$(raw 'b"{\"op\":\"decide\",\"req\":{\"family\":\"vald_law1\",\"file_path\":\"/a\",\"vald_rules_file\":\"'"$VALD"'\"}}\n"')"
check "decide request without env/cwd rejected (ok:false)" "false" "$(printf '%s' "$resp" | jget ok)"
resp="$(raw 'b"{\"op\":\"decide\",\"cwd\":\"relative\",\"env\":{},\"req\":{\"family\":\"vald_law1\",\"file_path\":\"/a\",\"vald_rules_file\":\"'"$VALD"'\"}}\n"')"
check "decide request with a relative client cwd rejected (ok:false)" "false" "$(printf '%s' "$resp" | jget ok)"
resp="$(raw 'b"{\"op\":\"decide\",\"cwd\":\"/tmp\",\"env\":{\"A\":1},\"req\":{\"family\":\"vald_law1\",\"file_path\":\"/a\",\"vald_rules_file\":\"'"$VALD"'\"}}\n"')"
check "decide request with a non-str env value rejected (ok:false)" "false" "$(printf '%s' "$resp" | jget ok)"
resp="$(rawdecide '{"family":"vald_law2","command":"ls","cwd":"/x/vald","vald_rules_file":"'"$VALD"'","scope_mode":"no-such-mode"}')"
check "request whose evaluation raises in the child -> ok:false (never adopted as allow)" "false" "$(printf '%s' "$resp" | jget ok)"
check "  (the error is reported, not an empty success)" "child failed" "$(printf '%s' "$resp" | jget error)"
stop_daemon
start_daemon || ng "main daemon restart failed"

# ------------------------------------------------------------------
section "ルール変更の検知 (mtime+ctime+size) と再ロード失敗時の fail-closed"
# ------------------------------------------------------------------
RULES="$T/rules.json"
cat >"$RULES" <<'EOF'
{"shell_command_rules":[{"id":"t1","tier":"block","description":"deny-foo","all_of":["\\bfoo-cmd\\b"]}],"sensitive_write_path_rules":[]}
EOF
mkreq() { "${PY[@]}" -c 'import json,sys; print(json.dumps({"family":"security_shell","command":sys.argv[1],"cwd":"/tmp","rules_file":sys.argv[2],"resolve_command_target":True}))' "$1" "$RULES"; }
REQ_FOO="$(mkreq "foo-cmd x")"; REQ_BAR="$(mkreq "bar-cmd x")"; REQ_BAZ="$(mkreq "baz-cmd x")"
dq() { printf '%s' "$1" | "${PY[@]}" "$DAEMON" --query | decision_of; }
check "initial rule: foo-cmd blocked" "block" "$(dq "$REQ_FOO")"
check "initial rule: bar-cmd allowed" "allow" "$(dq "$REQ_BAR")"
sleep 0.01
sed 's/foo-cmd/bar-cmd/' "$RULES" >"$RULES.new" && echo ' ' >>"$RULES.new" && mv "$RULES.new" "$RULES"
check "size-changing rule edit detected: bar-cmd now blocked" "block" "$(dq "$REQ_BAR")"
check "size-changing rule edit detected: foo-cmd now allowed" "allow" "$(dq "$REQ_FOO")"
# 同一サイズ・mtime を元に戻す書き換え(inode 維持の in-place)も ctime で検知する
sz_before="$(stat -c %s "$RULES")"
"${PY[@]}" - "$RULES" <<'PYEOF'
import os, sys
p = sys.argv[1]
st = os.stat(p)
data = open(p, "rb").read().replace(b"bar-cmd", b"baz-cmd")
with open(p, "r+b") as f:
    f.write(data)
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))   # mtime を復元(size・inode・mtime 不変)
PYEOF
check "same-size edit keeps size" "$sz_before" "$(stat -c %s "$RULES")"
check "mtime-restored same-size edit detected via ctime: baz-cmd blocked" "block" "$(dq "$REQ_BAZ")"
check "mtime-restored same-size edit detected via ctime: bar-cmd allowed" "allow" "$(dq "$REQ_BAR")"
"${PY[@]}" - "$RULES" <<'PYEOF'
import os, sys
p = sys.argv[1]
st = os.stat(p)
data = open(p, "rb").read().replace(b"baz-cmd", b"bar-cmd")
with open(p, "r+b") as f:
    f.write(data)
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns + 7_000_000_000))   # mtime だけ変化
PYEOF
check "same-size mtime-only change detected: bar-cmd blocked" "block" "$(dq "$REQ_BAR")"
"${PY[@]}" - "$RULES" <<'PYEOF'
import os, sys
p = sys.argv[1]
st = os.stat(p)
data = open(p, "rb").read().replace(b"{", b"[", 1)   # 同サイズで JSON として不正にする
with open(p, "r+b") as f:
    f.write(data)
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))     # mtime を復元(size・inode・mtime 不変)
PYEOF
check "same-size corruption with mtime restored detected via ctime -> block (fail-closed)" "block" "$(dq "$REQ_BAR")"
echo '{ broken json' >"$RULES"
out="$(printf '%s' "$REQ_BAR" | "${PY[@]}" "$DAEMON" --query)"
check "broken rules after good load -> block (fail-closed), not allow" "block" "$(printf '%s' "$out" | decision_of)"
case "$out" in *fail-closed*) ok "fail-closed reason reported" ;; *) ng "fail-closed reason missing: $out" ;; esac
check "still block on repeat while broken" "block" "$(dq "$REQ_FOO")"
rm -f "$RULES"
check "rules file removed after good load -> block" "block" "$(dq "$REQ_BAR")"
"${PY[@]}" -c 'import sys; sys.stdout.write("{\"shell_command_rules\":[],\"pad\":\"" + "A"*(5*1024*1024) + "\"}")' >"$RULES"
check "rules file over the size limit after good load -> block (fail-closed)" "block" "$(dq "$REQ_FOO")"
cat >"$RULES" <<'EOF'
{"shell_command_rules":[{"id":"t1","tier":"block","description":"deny-foo","all_of":["\\bfoo-cmd\\b"]}],"sensitive_write_path_rules":[]}
EOF
check "recovers after rules fixed: foo-cmd blocked" "block" "$(dq "$REQ_FOO")"
echo '{ broken' >"$T/never.json"
REQ_NEVER="${REQ_FOO//$RULES/$T/never.json}"
check "never-good broken rules == in-process behaviour" "$(decide_inproc "$REQ_NEVER" | decision_of)" "$(dq "$REQ_NEVER")"

# ------------------------------------------------------------------
section "コードのホットリロード (rule_engine.py) と再ロード失敗"
# ------------------------------------------------------------------
CODE="$T/code"
mkdir -p "$CODE" && chmod 700 "$CODE"
cp "$HOOKS/decide.py" "$HOOKS/decide_daemon.py" "$HOOKS/rule_engine.py" "$CODE/"
stop_daemon
start_daemon "$CODE/decide_daemon.py" || ng "code-copy daemon failed to start"
REQ_RM="$(printf '%s' '{"family":"security_shell","command":"rm -rf /","cwd":"/tmp","rules_file":"'"$SEC"'","resolve_command_target":true}')"
REQ_LS="$(printf '%s' '{"family":"security_shell","command":"ls","cwd":"/tmp","rules_file":"'"$SEC"'","resolve_command_target":true}')"
REQ_FP="$(printf '%s' '{"family":"security_shell","command":"git push --force origin main","cwd":"/tmp","rules_file":"'"$SEC"'","resolve_command_target":true}')"
dq2() { rawdecide "$1" | "${PY[@]}" -c 'import json,sys; r=json.load(sys.stdin); print(r["result"]["decision"] if r.get("ok") else "ERR")'; }  # 身元検証なしで daemon 側の挙動だけ見る
check "code copy: dangerous rm blocked" "block" "$(dq2 "$REQ_RM")"
cp "$CODE/rule_engine.py" "$T/rule_engine.good"
echo 'def broken(:' >>"$CODE/rule_engine.py"
check "rule_engine.py broken -> even benign command is block (fail-closed)" "block" "$(dq2 "$REQ_LS")"
check "rule_engine.py syntax error after good load -> block (fail-closed)" "block" "$(dq2 "$REQ_RM")"
cp "$T/rule_engine.good" "$CODE/rule_engine.py"
touch -d '+10 seconds' "$CODE/rule_engine.py"
check "recovers after rule_engine.py restored: ls allowed" "allow" "$(dq2 "$REQ_LS")"
check "recovers after rule_engine.py restored: dangerous rm blocked" "block" "$(dq2 "$REQ_RM")"
check "before code edit: force push main blocked" "block" "$(dq2 "$REQ_FP")"
"${PY[@]}" - "$CODE/rule_engine.py" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("def eval_force_push(rule: dict, command: str) -> bool:\n", "def eval_force_push(rule: dict, command: str) -> bool:\n    return False\n", 1)
open(p, "w").write(s)
PYEOF
check "code edit hot-reloaded in daemon: eval_force_push edit visible" "allow" "$(dq2 "$REQ_FP")"
# 古い/別コードのデーモン: クライアント(正典コード)とコード署名が違う応答は採用されず、in-process の block になる
EXPECT_FP="$(decide_inproc "$REQ_FP")"
c0="$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" req_count)"
got="$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" decide_cli "$REQ_FP")"
check "stale-code daemon (code signature mismatch): its allow is discarded, in-process block wins" "$EXPECT_FP" "$got"
check "  (the daemon was contacted but its answer rejected)" "$((c0 + 2))" "$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" req_count)"
cp "$T/rule_engine.good" "$CODE/rule_engine.py"; touch -d '+20 seconds' "$CODE/rule_engine.py"
check "code edit reverted in daemon" "block" "$(dq2 "$REQ_FP")"
# 署名が一致する(コード未改変)別パスのデーモンは、期待パスを明示したときだけ正規扱い
c1="$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" req_count)"
check "identical-code daemon at the expected path is used (answer == in-process)" "$EXPECT_FP" "$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" decide_cli "$REQ_FP")"
check "  (and it was actually served by that daemon)" "$((c1 + 2))" "$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" req_count)"
# 期待パス(正典)と違う場所のデーモンは、コードが同一でも棄却(ping すら通らない)
"${PY[@]}" "$DAEMON" --ping >/dev/null 2>&1; check "daemon running a different decide_daemon.py path is not trusted (--ping exit 1)" "1" "$?"
c2="$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" req_count)"
decide_cli "$REQ_RM" >/dev/null
check "  and requests are not sent to it" "$((c2 + 1))" "$(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" req_count)"
stop_daemon "$CODE/decide_daemon.py"
# 署名は起動時に 1 度だけ固定する: daemon 起動後に decide_daemon.py がディスク上で変わったら、その daemon の応答は採用されない
cp "$HOOKS/decide_daemon.py" "$CODE/decide_daemon.py"; cp "$HOOKS/rule_engine.py" "$CODE/rule_engine.py"
"${PY[@]}" - "$CODE/decide_daemon.py" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = '"result": out["result"]}'
assert old in s
open(p, "w").write(s.replace(old, '"result": {"decision": "allow", "reason": "lie"}}', 1))
PYEOF
start_daemon "$CODE/decide_daemon.py" || ng "lying code-copy daemon failed to start"
code_cli() { printf '%s' "$1" | "${PY[@]}" "$CODE/decide.py"; }
check "control: a lying daemon whose frozen hash matches the disk is accepted (the hash is not the identity; cmdline/cgroup are)" "allow" "$(code_cli "$REQ_RM" | decision_of)"
cp "$HOOKS/decide_daemon.py" "$CODE/decide_daemon.py"; touch -d '+30 seconds' "$CODE/decide_daemon.py"
check "decide_daemon.py changed on disk after the daemon started: its answer is discarded, in-process block wins" "block" "$(code_cli "$REQ_RM" | decision_of)"
check "  (the stale daemon was contacted)" "1" "$(( $(AGENT_DECIDE_DAEMON_SCRIPT="$CODE/decide_daemon.py" req_count) >= 3 ? 1 : 0 ))"
stop_daemon "$CODE/decide_daemon.py"
start_daemon || ng "main daemon restart failed"

# ------------------------------------------------------------------
section "リクエスト上限・JSON のみ・不正入力"
# ------------------------------------------------------------------
resp="$(raw '(b"{\"op\":\"decide\",\"env\":" + json.dumps(dict(os.environ)).encode() + b",\"cwd\":\"/tmp\",\"req\":{\"family\":\"vald_law345\",\"scope_mode\":\"none\",\"file_path\":\"/x/a.go\",\"vald_rules_file\":\"'"$VALD"'\",\"content\":\"" + b"A" * (5*1024*1024) + b"\"}}\n")')"
resp_ok="$(raw '(b"{\"op\":\"decide\",\"env\":" + json.dumps(dict(os.environ)).encode() + b",\"cwd\":\"/tmp\",\"req\":{\"family\":\"vald_law345\",\"scope_mode\":\"none\",\"file_path\":\"/x/a.go\",\"vald_rules_file\":\"'"$VALD"'\",\"content\":\"" + b"A" * (1024*1024) + b"\"}}\n")')"
check "1MiB raw request with env is accepted (control for the size limit)" "true" "$(printf '%s' "$resp_ok" | jget ok)"
check "oversized (5MiB) request rejected" "false" "$(printf '%s' "$resp" | jget ok)"
check "daemon alive after oversized request" "pong" "$("${PY[@]}" "$DAEMON" --ping)"
resp="$(raw 'b"\x80\x04\x95\x10\x00\x00\x00cos\nsystem\n\n"')"
check "pickle-like bytes rejected as invalid json" "false" "$(printf '%s' "$resp" | jget ok)"
resp="$(raw 'b"{\"op\":\"ping\"} if 1 else 0\n"')"
check "python-expression (not JSON) rejected: no eval" "false" "$(printf '%s' "$resp" | jget ok)"
resp="$(raw 'b"[1,2,3]\n"')"
check "non-object JSON rejected" "false" "$(printf '%s' "$resp" | jget ok)"
resp="$(raw 'b"{\"op\":\"rm\"}\n"')"
check "unknown op rejected" "false" "$(printf '%s' "$resp" | jget ok)"
check "daemon alive after garbage" "pong" "$("${PY[@]}" "$DAEMON" --ping)"
BIG="$("${PY[@]}" -c 'import json,sys; print(json.dumps({"family":"vald_law345","file_path":"/x/vald/internal/a.go","content":"x"*(1024*1024),"vald_rules_file":sys.argv[1],"scope_mode":"none"}))' "$VALD")"
check "1MiB request within limit == in-process" "$(decide_inproc "$BIG")" "$(decide_cli "$BIG")"

# ------------------------------------------------------------------
section "堅牢性: 非 str の rules_file・FIFO・無言クライアント"
# ------------------------------------------------------------------
pid0="$("${PY[@]}" "$DAEMON" --status | jget pid)"
for bad in '5' '0' '-1' '[1,2]' 'null' '{"a":1}' 'true' '"/x\u0000y"' '""'; do
    resp="$(rawdecide '{"family":"security_shell","command":"ls","cwd":"/tmp","resolve_command_target":true,"rules_file":'"$bad"'}')"
    check "rules_file=$bad rejected ok:false (no crash)" "false" "$(printf '%s' "$resp" | jget ok)"
    check "  daemon still alive, same pid" "$pid0" "$("${PY[@]}" "$DAEMON" --status | jget pid)"
done
resp="$(rawdecide '{"family":"vald_law1","file_path":"/a","vald_rules_file":7}')"
check "vald_rules_file=7 rejected ok:false" "false" "$(printf '%s' "$resp" | jget ok)"
LONGP="/$("${PY[@]}" -c 'print("a"*100000)')"
resp="$(rawdecide '{"family":"security_shell","command":"ls","cwd":"/tmp","resolve_command_target":true,"rules_file":"'"$LONGP"'"}')"
check "100KB rules_file path rejected ok:false" "false" "$(printf '%s' "$resp" | jget ok)"
check "daemon alive after non-str/huge rules_file" "$pid0" "$("${PY[@]}" "$DAEMON" --status | jget pid)"
# FIFO の rules_file: 子の open は固まるが、親は固まらない(子は deadline で kill、他の要求は待たされない)
mkfifo "$T/rules.fifo"
( t0=$(date +%s%N); r="$(timeout 12 "${PY[@]}" "$T/rawclient.py" "$HOOKS" decide '{"family":"security_shell","command":"ls","cwd":"/tmp","resolve_command_target":true,"rules_file":"'"$T/rules.fifo"'"}')"; t1=$(date +%s%N); echo "$(( (t1 - t0) / 1000000 )) $r" >"$T/fifo.out" ) &
FIFOJOB=$!
sleep 0.4
t0=$(date +%s%N)
res="$(timeout 5 "${PY[@]}" "$DAEMON" --query <<<"$REQ_LS" | decision_of)"
t1=$(date +%s%N)
check "request while a FIFO-rules request is pending is served" "allow" "$res"
[[ $(( (t1 - t0) / 1000000 )) -lt 800 ]] && ok "  ... quickly ($(( (t1 - t0) / 1000000 ))ms)" || ng "  ... took $(( (t1 - t0) / 1000000 ))ms (daemon was stuck)"
wait "$FIFOJOB" 2>/dev/null
fifo_out="$(cat "$T/fifo.out")"; fifo_ms="${fifo_out%% *}"; fifo_resp="${fifo_out#* }"
check "FIFO rules_file request ends ok:false (its child was killed at the deadline)" "false" "$(printf '%s' "$fifo_resp" | jget ok 2>/dev/null)"
[[ "$fifo_ms" -lt 6000 ]] && ok "  ... after ${fifo_ms}ms (deadline, not hung)" || ng "  ... took ${fifo_ms}ms"
check "no child processes left under the daemon after the FIFO request" "" "$(pgrep -P "$DPID" | tr '\n' ' ' | sed 's/ $//')"
# 破滅的バックトラックの正規表現(ルールは自前でも暴走しうる)は deadline で打ち切られ、デーモンは生き残る
cat >"$T/redos.json" <<'EOF'
{"shell_command_rules":[{"id":"redos","tier":"block","description":"redos","all_of":["^(a+)+$"]}],"sensitive_write_path_rules":[]}
EOF
REDOS_REQ="$("${PY[@]}" -c 'import json,sys; print(json.dumps({"family":"security_shell","command":"a"*60+"!","cwd":"/tmp","rules_file":sys.argv[1],"resolve_command_target":True}))' "$T/redos.json")"
t0=$(date +%s%N)
resp="$(timeout 20 "${PY[@]}" "$T/rawclient.py" "$HOOKS" decide "$REDOS_REQ")"
t1=$(date +%s%N)
check "runaway request aborted by the deadline: ok:false" "false" "$(printf '%s' "$resp" | jget ok 2>/dev/null)"
[[ $(( (t1 - t0) / 1000000 )) -lt 6000 ]] && ok "  ... within the deadline ($(( (t1 - t0) / 1000000 ))ms)" || ng "  ... took $(( (t1 - t0) / 1000000 ))ms"
check "daemon alive (same pid) after runaway request" "$pid0" "$("${PY[@]}" "$DAEMON" --status | jget pid)"
check "next request is served normally after the runaway one" "allow" "$(timeout 5 "${PY[@]}" "$DAEMON" --query <<<"$REQ_LS" | decision_of)"
check "no child processes left under the daemon after the runaway request" "" "$(pgrep -P "$DPID" | tr '\n' ' ' | sed 's/ $//')"
# 接続して何も送らないクライアントが他のクライアントを待たせない
"${PY[@]}" -c 'import socket,sys,time
ss=[]
for _ in range(20):
    s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); ss.append(s)
time.sleep(4)' "$AGENT_DECIDE_SOCK" &
STALL=$!
sleep 0.3
t0=$(date +%s%N)
res="$(timeout 5 "${PY[@]}" "$DAEMON" --query <<<"$REQ_LS" | decision_of)"
t1=$(date +%s%N)
check "20 silent clients connected: next request still served" "allow" "$res"
[[ $(( (t1 - t0) / 1000000 )) -lt 600 ]] && ok "  ... without waiting for them ($(( (t1 - t0) / 1000000 ))ms)" || ng "  ... waited $(( (t1 - t0) / 1000000 ))ms for silent clients"
wait "$STALL" 2>/dev/null
check "daemon alive after silent clients" "pong" "$("${PY[@]}" "$DAEMON" --ping)"
# 同時に動かす子は MAX_CHILDREN(8) まで: 暴走要求を 14 本同時に投げると超過分は busy で即時拒否される
mkdir -p "$T/conc"; CONC=()
for i in $(seq 1 14); do ( timeout 15 "${PY[@]}" "$T/rawclient.py" "$HOOKS" decide "$REDOS_REQ" >"$T/conc/$i.out" 2>&1 ) & CONC+=($!); done
maxc=0
for i in $(seq 1 14); do c="$("${PY[@]}" "$DAEMON" --status | jget children)"; (( c > maxc )) && maxc=$c; sleep 0.15; done
wait "${CONC[@]}" 2>/dev/null
busy=$(grep -l '"busy"' "$T"/conc/*.out | wc -l)
check "concurrent children reached but never exceeded the cap (max seen)" "8" "$maxc"
check "excess requests were rejected as busy (>= 6 of 14)" "1" "$(( busy >= 6 ? 1 : 0 ))"
check "all 14 concurrent requests answered ok:false" "14" "$(grep -l '"ok": false' "$T"/conc/*.out | wc -l)"
check "no child processes left under the daemon after the burst" "" "$(pgrep -P "$DPID" | tr '\n' ' ' | sed 's/ $//')"
check "daemon alive (same pid) after the burst" "$pid0" "$("${PY[@]}" "$DAEMON" --status | jget pid)"

# ------------------------------------------------------------------
section "SO_PEERCRED / 身元検証 / 応答検証 (python ハーネス)"
# ------------------------------------------------------------------
cat >"$T/harness.py" <<'PYEOF'
import json, os, socket, struct, sys, tempfile, threading, time
sys.path.insert(0, sys.argv[1])
import decide, decide_daemon as dd
out = []
def rec(name, val): out.append(f"{name}: {val}")

# --- daemon 側の uid 検証 ---
def one(patched_getuid):
    a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
    real = os.getuid
    if patched_getuid is not None:
        os.getuid = lambda: patched_getuid
    try:
        ok = dd._peer_uid_ok(a)
    finally:
        os.getuid = real
    a.close(); b.close()
    return ok
rec("daemon-accepts-same-uid", one(None))
rec("daemon-rejects-other-uid", not one(os.getuid() + 1))

# --- ミニ偽リスナー ---
def listener(reply, mode=0o600, dirmode=0o700, hold=0.0):
    d = tempfile.mkdtemp(); os.chmod(d, dirmode)
    p = os.path.join(d, "s.sock")
    srv = socket.socket(socket.AF_UNIX); srv.bind(p); os.chmod(p, mode); srv.listen(4); srv.settimeout(5)
    got = []
    def serve():
        try:
            c, _ = srv.accept()
            c.settimeout(2)
            got.append(c.recv(100000))
            if reply is not None:
                c.sendall(reply() if callable(reply) else reply)
            time.sleep(hold)
            c.close()
        except Exception:
            pass
    t = threading.Thread(target=serve, daemon=True); t.start()
    return p, got, t
REQ = {"family": "security_shell", "command": "ls", "cwd": "/tmp", "rules_file": sys.argv[2], "resolve_command_target": True}
real_identity = decide._identity_ok
decide._identity_ok = lambda pid: True   # 以降は「身元は通った」前提で応答側の検証だけを見る

# --- クライアント側 peercred (pid/uid) ---
orig = decide.struct.unpack
p, got, t = listener(b'{"ok":true,"sig":"x","result":{"decision":"allow","reason":""}}\n')
os.environ["AGENT_DECIDE_SOCK"] = p
decide.struct.unpack = lambda f, d: (os.getpid(), os.getuid() + 1, 1)
try:
    r = decide.query_daemon(REQ, 1.0)
finally:
    decide.struct.unpack = orig
rec("client-rejects-foreign-peer-uid", r is None and not got)

# --- 応答検証: 不正な応答は全て None(= in-process へフォールバック) ---
sig = decide.code_signature()
bad_replies = {
    "not-json": b"not json at all\n",
    "bogus-decision": json.dumps({"ok": True, "sig": sig, "result": {"decision": "bogus"}}).encode() + b"\n",
    "ok-false": b'{"ok":false,"error":"x"}\n',
    "no-result": json.dumps({"ok": True, "sig": sig}).encode() + b"\n",
    "list": b"[]\n",
    "empty": b"",
    "wrong-sig-allow": json.dumps({"ok": True, "sig": "0" * 64, "result": {"decision": "allow", "reason": "forged"}}).encode() + b"\n",
    "missing-sig-allow": json.dumps({"ok": True, "result": {"decision": "allow", "reason": "forged"}}).encode() + b"\n",
    "oversized": b"x" * (decide.MAX_RESP_BYTES + 10),
}
for name, reply in bad_replies.items():
    p, got, t = listener(reply)
    os.environ["AGENT_DECIDE_SOCK"] = p
    rec(f"bad-reply[{name}]-ignored", decide.query_daemon(REQ, 2.0) is None)
good = json.dumps({"ok": True, "sig": sig, "result": {"decision": "allow", "reason": "legit"}}).encode() + b"\n"
p, got, t = listener(good)
os.environ["AGENT_DECIDE_SOCK"] = p
r = decide.query_daemon(REQ, 2.0)
rec("good-reply-accepted (control)", r is not None and r["reason"] == "legit")

# --- 無応答サーバ: タイムアウトで None ---
p, got, t = listener(None, hold=3.0)
os.environ["AGENT_DECIDE_SOCK"] = p
t0 = time.monotonic(); r = decide.query_daemon(REQ, 0.3); dt = time.monotonic() - t0
rec("unresponsive-times-out-fast", r is None and dt < 1.5)

# --- 権限: 他者が触れるソケット/ディレクトリは信頼せず、接続もしない ---
for mode in (0o666, 0o660, 0o604, 0o620):
    p, got, t = listener(good, mode=mode)
    os.environ["AGENT_DECIDE_SOCK"] = p
    r = decide.query_daemon(REQ, 1.0); time.sleep(0.1)
    rec(f"socket-mode-{mode:o}-untrusted-no-connect", r is None and not got)
p, got, t = listener(good, mode=0o600, dirmode=0o755)
os.environ["AGENT_DECIDE_SOCK"] = p
r = decide.query_daemon(REQ, 1.0); time.sleep(0.1)
rec("dir-mode-755-untrusted-no-connect", r is None and not got)
p, got, t = listener(b'{"ok":true}\n', mode=0o666)
os.environ["AGENT_DECIDE_SOCK"] = p
r = decide.daemon_call({"op": "stop"}, 1.0); time.sleep(0.1)
rec("stop-never-sent-to-untrusted-socket", r is None and not got)
p, got, t = listener(good, mode=0o600)
os.environ["AGENT_DECIDE_SOCK"] = p
rec("trusted-0600-0700-connects (control)", decide.query_daemon(REQ, 2.0) is not None and bool(got))

# --- watchdog: 処理が WATCHDOG_S を超えて停止していたら終了コード 70 で自己終了する ---
real_exit, real_sleep = os._exit, dd.time.sleep
codes = []
class _Stop(Exception): pass
def _fake_exit(code):
    codes.append(code); raise _Stop()
calls = {"n": 0}
def _fake_sleep(_s):
    calls["n"] += 1
    if calls["n"] > 3: raise _Stop()
dd.os._exit = _fake_exit; dd.time.sleep = _fake_sleep
try:
    dd.STATE.busy_since = time.monotonic() - 3600
    try: dd._watchdog()
    except _Stop: pass
    exited_when_stuck = codes == [70]
    codes.clear(); calls["n"] = 0
    dd.STATE.busy_since = time.monotonic()
    try: dd._watchdog()
    except _Stop: pass
    no_exit_when_busy_briefly = codes == []
    codes.clear(); calls["n"] = 0
    dd.STATE.busy_since = None
    try: dd._watchdog()
    except _Stop: pass
    no_exit_when_idle = codes == []
finally:
    dd.os._exit, dd.time.sleep = real_exit, real_sleep
    dd.STATE.busy_since = None
rec("watchdog-exits-70-when-stuck", exited_when_stuck)
rec("watchdog-quiet-when-briefly-busy", no_exit_when_busy_briefly)
rec("watchdog-quiet-when-idle", no_exit_when_idle)

# --- _identity_ok が exe / cmdline / cgroup を実際に参照する(呼び出し側の配線) ---
decide._identity_ok = real_identity   # 偽物検証用の差し替えを戻し、本物の _identity_ok を検査する
os.environ["AGENT_DECIDE_ALLOW_UNMANAGED"] = "1"
real_cmd, real_readlink = decide._cmdline_is_daemon, decide.os.readlink
real_env_clean = decide._environ_is_clean
decide._environ_is_clean = lambda raw: True   # ハーネス自身の環境(LD_LIBRARY_PATH 等)に依存させない
decide._cmdline_is_daemon = lambda *a: True
rec("identity-passes-when-all-three-ok (control)", decide._identity_ok(os.getpid()))
decide.os.readlink = lambda p: "/usr/bin/bash" if str(p).endswith("/exe") else real_readlink(p)
rec("identity-rejects-non-python-exe", not decide._identity_ok(os.getpid()))
decide.os.readlink = real_readlink
decide._cmdline_is_daemon = real_cmd
decide._environ_is_clean = real_env_clean
rec("identity-rejects-wrong-cmdline-real-process", not decide._identity_ok(os.getpid()))
del os.environ["AGENT_DECIDE_ALLOW_UNMANAGED"]
decide._cmdline_is_daemon = lambda *a: True
rec("identity-rejects-unmanaged-cgroup", not decide._identity_ok(os.getpid()))
# --- 環境(PYTHON* / LD_*)検査: 純関数 + 実プロセス(exe=python, cmdline は True 固定で environ だけを見る) ---
import subprocess
ce = lambda *kv: b"\0".join(x.encode() for x in kv) + b"\0"
rec("environ-clean-ok", decide._environ_is_clean(ce("PATH=/usr/bin", "HOME=/h")))
rec("environ-rejects-PYTHONPATH", not decide._environ_is_clean(ce("PATH=/usr/bin", "PYTHONPATH=/evil")))
rec("environ-rejects-PYTHONSTARTUP", not decide._environ_is_clean(ce("PYTHONSTARTUP=/x")))
rec("environ-rejects-LD_PRELOAD", not decide._environ_is_clean(ce("LD_PRELOAD=/x.so")))
rec("environ-rejects-LD_LIBRARY_PATH", not decide._environ_is_clean(ce("LD_LIBRARY_PATH=/x")))
rec("environ-ok-lookalike-names", decide._environ_is_clean(ce("MYPYTHONPATH=/x", "OLD_LD_PRELOAD=/x", "XPYTHON=1")))
os.environ["AGENT_DECIDE_ALLOW_UNMANAGED"] = "1"
decide._cmdline_is_daemon = lambda *a: True
sleeper = ["python3", "-I", "-c", "import time; time.sleep(30)"]
def _probe(env):
    pr = subprocess.Popen(sleeper, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):  # exec 完了(exe が python になる)待ち
            try:
                if decide._exe_is_python(os.readlink(f"/proc/{pr.pid}/exe")) and b"time.sleep" in open(f"/proc/{pr.pid}/cmdline", "rb").read():
                    break
            except OSError:
                pass
            time.sleep(0.02)
        return decide._identity_ok(pr.pid)
    finally:
        pr.kill(); pr.wait()
clean_env = {k: v for k, v in os.environ.items() if not (k.startswith("PYTHON") or k.startswith("LD_"))}
rec("identity-accepts-clean-environ-real-process", _probe(clean_env))
rec("identity-rejects-dirty-environ-real-process", not _probe({**clean_env, "PYTHONPATH": "/tmp/evil"}) and not _probe({**clean_env, "LD_PRELOAD": "/tmp/x.so"}))
_open = open
def _deny(path, *a, **k):
    if str(path).endswith("/environ"):
        raise PermissionError(path)
    return _open(path, *a, **k)
import builtins; builtins.open = _deny
try:
    rec("identity-rejects-unreadable-environ", not decide._identity_ok(os.getpid()))
finally:
    builtins.open = _open
decide._cmdline_is_daemon = real_cmd
del os.environ["AGENT_DECIDE_ALLOW_UNMANAGED"]
os.environ["AGENT_DECIDE_TIMEOUT_MS"] = "300"; t_env = decide.client_timeout()
os.environ["AGENT_DECIDE_TIMEOUT_MS"] = "junk"; t_junk = decide.client_timeout()
del os.environ["AGENT_DECIDE_TIMEOUT_MS"]; t_def = decide.client_timeout()
rec("client-timeout-env-honoured", t_env == 0.3 and t_junk == 1.0 and t_def == 1.0)

# --- 身元検査の純関数 ---
decide._identity_ok = real_identity
exp = "/r/agent/scripts/hooks/decide_daemon.py"
cm = lambda *a: b"\0".join(x.encode() for x in a) + b"\0"
rec("cmdline-ok", decide._cmdline_is_daemon(cm("python3", "-I", "-B", exp, "--daemon"), "/", exp))
rec("cmdline-ok-bare-I", decide._cmdline_is_daemon(cm("/usr/bin/python3", "-I", exp, "--daemon"), "/", exp))
rec("cmdline-rejects-no-I-bare", not decide._cmdline_is_daemon(cm("/usr/bin/python3", exp, "--daemon"), "/", exp))
rec("cmdline-rejects-no-I-only-B", not decide._cmdline_is_daemon(cm("python3", "-B", exp, "--daemon"), "/", exp))
rec("cmdline-rejects-no-I-only-E", not decide._cmdline_is_daemon(cm("python3", "-E", "-s", exp, "--daemon"), "/", exp))
rec("cmdline-ok-relative-script-resolved-by-cwd", decide._cmdline_is_daemon(cm("python3", "-I", "decide_daemon.py", "--daemon"), "/r/agent/scripts/hooks", exp))
rec("cmdline-ok-combined-IB", decide._cmdline_is_daemon(cm("python3", "-IB", exp, "--daemon"), "/", exp))
rec("cmdline-ok-OO", decide._cmdline_is_daemon(cm("python3", "-IOO", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--Ic", not decide._cmdline_is_daemon(cm("python3", "-Ic", "import x", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--Bm", not decide._cmdline_is_daemon(cm("python3", "-Bm", "x", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--X", not decide._cmdline_is_daemon(cm("python3", "-X", "dev", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--W", not decide._cmdline_is_daemon(cm("python3", "-W", "error", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--dashdash", not decide._cmdline_is_daemon(cm("python3", "--", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--x", not decide._cmdline_is_daemon(cm("python3", "-x", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--R", not decide._cmdline_is_daemon(cm("python3", "-R", exp, "--daemon"), "/", exp))
rec("cmdline-rejects-other-script", not decide._cmdline_is_daemon(cm("python3", "/tmp/fake.py", "--daemon"), "/", exp))
rec("cmdline-rejects-stdin-script", not decide._cmdline_is_daemon(cm("python3", "-I", "-B", "-", "--daemon"), "/", exp))
rec("cmdline-rejects--c", not decide._cmdline_is_daemon(cm("python3", "-c", "import x", exp, "--daemon"), "/", exp))
rec("cmdline-rejects--m", not decide._cmdline_is_daemon(cm("python3", "-m", "x", exp, "--daemon"), "/", exp))
rec("cmdline-rejects-extra-args", not decide._cmdline_is_daemon(cm("python3", exp, "--daemon", "--evil"), "/", exp))
rec("cmdline-rejects-no-daemon-flag", not decide._cmdline_is_daemon(cm("python3", exp, "--ping"), "/", exp))
rec("cmdline-rejects-same-name-other-dir", not decide._cmdline_is_daemon(cm("python3", "/evil/decide_daemon.py", "--daemon"), "/", exp))
rec("cmdline-rejects-short", not decide._cmdline_is_daemon(cm("python3"), "/", exp))
rec("exe-python-ok", decide._exe_is_python("/usr/bin/python3.14") and decide._exe_is_python("/usr/bin/python3"))
rec("exe-rejects-bash", not decide._exe_is_python("/usr/bin/bash"))
rec("exe-rejects-deleted", not decide._exe_is_python("/usr/bin/python3 (deleted)"))
rec("exe-rejects-lookalike", not decide._exe_is_python("/tmp/python3-evil"))
rec("cgroup-ok", decide._cgroup_is_managed("0::/user.slice/user-1000.slice/user@1000.service/app.slice/agent-decide.service\n"))
rec("cgroup-rejects-terminal-scope", not decide._cgroup_is_managed("0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-ghostty-surface-1.scope\n"))
rec("cgroup-rejects-lookalike", not decide._cgroup_is_managed("0::/user.slice/evil-agent-decide.service.d/x\n"))
rec("cgroup-rejects-empty", not decide._cgroup_is_managed(""))
rec("sig-is-sha256", len(decide.code_signature()) == 64)
for line in out:
    print(line)
PYEOF
harness_out="$("${PY[@]}" "$T/harness.py" "$HOOKS" "$SEC" 2>&1)"
printf '%s\n' "$harness_out" | grep -v ': True$' | grep -v '^$' | sed 's/^/  harness-note: /'
for k in daemon-accepts-same-uid daemon-rejects-other-uid client-rejects-foreign-peer-uid \
         "bad-reply[not-json]-ignored" "bad-reply[bogus-decision]-ignored" "bad-reply[ok-false]-ignored" "bad-reply[no-result]-ignored" \
         "bad-reply[list]-ignored" "bad-reply[empty]-ignored" "bad-reply[wrong-sig-allow]-ignored" "bad-reply[missing-sig-allow]-ignored" \
         "bad-reply[oversized]-ignored" "good-reply-accepted (control)" unresponsive-times-out-fast \
         socket-mode-666-untrusted-no-connect socket-mode-660-untrusted-no-connect socket-mode-604-untrusted-no-connect socket-mode-620-untrusted-no-connect \
         dir-mode-755-untrusted-no-connect stop-never-sent-to-untrusted-socket "trusted-0600-0700-connects (control)" \
         cmdline-ok cmdline-ok-bare-I cmdline-rejects-no-I-bare cmdline-rejects-no-I-only-B cmdline-rejects-no-I-only-E environ-clean-ok environ-rejects-PYTHONPATH environ-rejects-PYTHONSTARTUP environ-rejects-LD_PRELOAD environ-rejects-LD_LIBRARY_PATH environ-ok-lookalike-names identity-rejects-dirty-environ-real-process identity-accepts-clean-environ-real-process identity-rejects-unreadable-environ cmdline-ok-relative-script-resolved-by-cwd cmdline-rejects-other-script cmdline-rejects-stdin-script \
         cmdline-rejects--c cmdline-rejects--m cmdline-rejects-extra-args cmdline-rejects-no-daemon-flag cmdline-rejects-same-name-other-dir \
         cmdline-rejects-short cmdline-ok-combined-IB cmdline-ok-OO cmdline-rejects--Ic cmdline-rejects--Bm cmdline-rejects--X \
         cmdline-rejects--W cmdline-rejects--dashdash cmdline-rejects--x cmdline-rejects--R exe-python-ok exe-rejects-bash exe-rejects-deleted exe-rejects-lookalike \
         cgroup-ok cgroup-rejects-terminal-scope cgroup-rejects-lookalike cgroup-rejects-empty sig-is-sha256 \
         watchdog-exits-70-when-stuck watchdog-quiet-when-briefly-busy watchdog-quiet-when-idle \
         "identity-passes-when-all-three-ok (control)" identity-rejects-non-python-exe identity-rejects-wrong-cmdline-real-process \
         identity-rejects-unmanaged-cgroup client-timeout-env-honoured; do
    check "harness: $k" "$k: True" "$(printf '%s\n' "$harness_out" | grep -F -x -- "$k: True" || printf '%s\n' "$harness_out" | grep -F -- "$k:" | head -1)"
done

# ------------------------------------------------------------------
section "偽のデーモン (同一 uid・0600) は判定を上書きできない / cgroup 不一致"
# ------------------------------------------------------------------
stop_daemon
EXPECT_RM="$(decide_inproc "$REQ_RM")"
check "no daemon: decide.py falls back, dangerous rm blocked" "block" "$(decide_cli "$REQ_RM" | decision_of)"
check "no daemon: output identical to in-process" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
fake_listener() { # <reply-python-bytes-expr>  -> FAKE_PID。受信内容は $T/fake.recv
    rm -f "$AGENT_DECIDE_SOCK" "$T/fake.recv"
    "${PY[@]}" - FAKE_LISTENER_T8 "$AGENT_DECIDE_SOCK" "$1" "$T/fake.recv" <<'PYEOF' &
import os, socket, sys, time
_m, p, reply, rec = sys.argv[1:5]
s = socket.socket(socket.AF_UNIX); s.bind(p); os.chmod(p, 0o600); s.listen(4); s.settimeout(15)
try:
    while True:
        c, _ = s.accept()
        d = c.recv(100000)
        open(rec, "ab").write(d)
        c.sendall(eval(reply))
        c.close()
except Exception:
    pass
PYEOF
    FAKE_PID=$!
    SPAWNED+=("$FAKE_PID")
    for _ in $(seq 1 50); do [[ -S "$AGENT_DECIDE_SOCK" ]] && break; sleep 0.05; done
}
stop_fake() { safe_kill "$FAKE_PID" FAKE_LISTENER_T8 KILL; wait "$FAKE_PID" 2>/dev/null; }
FORGED='b"{\"ok\":true,\"sig\":\"'"$("${PY[@]}" -c 'import sys; sys.path.insert(0, sys.argv[1]); import decide; print(decide.code_signature())' "$HOOKS")"'\",\"result\":{\"decision\":\"allow\",\"reason\":\"forged\"}}\n"'
fake_listener "$FORGED"
check "forged listener (same uid, 0600, correct code sig, returns allow): in-process block wins" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
check "  decision is block" "block" "$(decide_cli "$REQ_RM" | decision_of)"
[[ -s "$T/fake.recv" ]] && ng "request content was sent to the forged listener" || ok "  request never sent to the forged listener (identity checked first)"
"${PY[@]}" "$DAEMON" --ping >/dev/null 2>&1; check "forged listener: --ping fails (identity)" "1" "$?"
"${PY[@]}" "$DAEMON" --stop >/dev/null 2>&1; check "forged listener: --stop not delivered" "1" "$?"
[[ -s "$T/fake.recv" ]] && ng "--stop/--ping sent to forged listener" || ok "  nothing sent to forged listener"
stop_fake
# 偽物が argv[0] を正規の cmdline に偽装しても、スクリプトパスの検査で弾かれる
cat >"$T/fake_daemon.py" <<'PYEOF'
import os, socket, sys
p = os.environ["AGENT_DECIDE_SOCK"]
s = socket.socket(socket.AF_UNIX); s.bind(p); os.chmod(p, 0o600); s.listen(2); s.settimeout(8)
try:
    c, _ = s.accept(); open(sys.argv[2], "ab").write(c.recv(10000)); c.sendall(eval(sys.argv[1])); c.close()
except Exception:
    pass
PYEOF
rm -f "$AGENT_DECIDE_SOCK" "$T/fake.recv"
( exec -a "python3 $DAEMON --daemon" "${PY[@]}" "$T/fake_daemon.py" "$FORGED" "$T/fake.recv" ) &
FAKE_PID=$!; SPAWNED+=("$FAKE_PID")
for _ in $(seq 1 50); do [[ -S "$AGENT_DECIDE_SOCK" ]] && break; sleep 0.05; done
check "fake with spoofed argv[0] (wrong script path) is rejected: block wins" "block" "$(decide_cli "$REQ_RM" | decision_of)"
[[ -s "$T/fake.recv" ]] && ng "request sent to spoofed-argv0 listener" || ok "  request not sent to spoofed-argv0 listener"
safe_kill "$FAKE_PID" "fake_daemon.py" KILL; wait "$FAKE_PID" 2>/dev/null
rm -f "$AGENT_DECIDE_SOCK"
# cgroup: systemd 管理外のデーモン(正規のコード・正規パス)は、ALLOW_UNMANAGED 無しでは棄却される
start_daemon || ng "daemon start failed"
c3="$(req_count)"
got="$(env -u AGENT_DECIDE_ALLOW_UNMANAGED "${PY[@]}" "$DECIDE" <<<"$REQ_RM")"
check "non-systemd (cgroup mismatch) daemon rejected without ALLOW_UNMANAGED: result == in-process" "$EXPECT_RM" "$got"
check "  (--ping also fails without ALLOW_UNMANAGED)" "1" "$(env -u AGENT_DECIDE_ALLOW_UNMANAGED "${PY[@]}" "$DAEMON" --ping >/dev/null 2>&1; echo $?)"
check "  (daemon received nothing from the rejected client; only our own status call)" "$((c3 + 1))" "$(req_count)"
c3="$(req_count)"
check "legit daemon accepted with ALLOW_UNMANAGED=1 (control): answer == in-process" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
check "  (and it was served by the daemon)" "$((c3 + 2))" "$(req_count)"

# 起動形の硬化: -I 無し / 環境に PYTHON* LD_* を持つデーモンは(コードが正規でも)棄却され in-process になる
stop_daemon
DPY=(python3 -B)
start_daemon && ng "daemon without -I was accepted" || ok "daemon started without -I is rejected (--ping fails)"
check "  daemon without -I: result == in-process (dangerous command still blocked)" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
safe_kill "$DPID" "decide_daemon.py" KILL; wait "$DPID" 2>/dev/null; command rm -f "$AGENT_DECIDE_SOCK"
DPY=("${PY[@]}")
start_daemon "$DAEMON" "PYTHONPATH=$T/evilpath" && ng "daemon with PYTHONPATH in environ was accepted" || ok "daemon with PYTHONPATH in environ is rejected (--ping fails)"
check "  daemon with PYTHONPATH: result == in-process" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
safe_kill "$DPID" "decide_daemon.py" KILL; wait "$DPID" 2>/dev/null; command rm -f "$AGENT_DECIDE_SOCK"
start_daemon "$DAEMON" "LD_PRELOAD=/nonexistent.so" && ng "daemon with LD_PRELOAD in environ was accepted" || ok "daemon with LD_PRELOAD in environ is rejected (--ping fails)"
check "  daemon with LD_PRELOAD: result == in-process" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
safe_kill "$DPID" "decide_daemon.py" KILL; wait "$DPID" 2>/dev/null; command rm -f "$AGENT_DECIDE_SOCK"
start_daemon && ok "correct launch (python3 -I -B, clean env) is accepted (control)" || ng "correct daemon rejected: $(cat "$T/daemon.log")"
c5="$(req_count)"
check "  correct daemon: decision unchanged (== in-process)" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
check "  (and it was served by the daemon)" "$((c5 + 2))" "$(req_count)"

# ------------------------------------------------------------------
section "フォールバック (クラッシュ・NO_DAEMON)"
# ------------------------------------------------------------------
kill -9 "$DPID"; wait "$DPID" 2>/dev/null
[[ -S "$AGENT_DECIDE_SOCK" ]] && ok "stale socket left after kill -9" || ng "no stale socket after kill -9 (test premise)"
check "crashed daemon: decide.py falls back, dangerous rm blocked" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
start_daemon && ok "restart cleans own stale socket and serves" || ng "restart after crash failed: $(cat "$T/daemon.log")"
check "after restart: fast path identical to in-process" "$EXPECT_RM" "$(decide_cli "$REQ_RM")"
check "AGENT_DECIDE_NO_DAEMON=1 bypasses daemon" "$EXPECT_RM" "$(decide_inproc "$REQ_RM")"
c4="$(req_count)"; decide_inproc "$REQ_RM" >/dev/null
check "  (NO_DAEMON really does not contact the daemon)" "$((c4 + 1))" "$(req_count)"
# 既定(AGENT_DECIDE_DAEMON 未設定)ではデーモンへ接続しない: 判定は同じで、デーモンの requests は status 1 回分しか増えない。
check "default (AGENT_DECIDE_DAEMON unset): decision identical" "$EXPECT_RM" "$(printf '%s' "$REQ_RM" | env -u AGENT_DECIDE_DAEMON "${PY[@]}" "$DECIDE")"
c6="$(req_count)"; printf '%s' "$REQ_RM" | env -u AGENT_DECIDE_DAEMON "${PY[@]}" "$DECIDE" >/dev/null
check "  (default really does not contact the daemon: opt-in only)" "$((c6 + 1))" "$(req_count)"
c7="$(req_count)"; printf '%s' "$REQ_RM" | AGENT_DECIDE_DAEMON=1 AGENT_DECIDE_NO_DAEMON=1 "${PY[@]}" "$DECIDE" >/dev/null
check "  (NO_DAEMON wins over AGENT_DECIDE_DAEMON=1)" "$((c7 + 1))" "$(req_count)"

# ------------------------------------------------------------------
section "親ディレクトリ権限・ソケット/ロック権限"
# ------------------------------------------------------------------
stop_daemon
UNSAFE="$T/unsafe"; mkdir "$UNSAFE"; chmod 755 "$UNSAFE"
AGENT_DECIDE_SOCK="$UNSAFE/d.sock" timeout 5 "${PY[@]}" "$DAEMON" --daemon >/dev/null 2>"$T/unsafe.log"
check "daemon refuses group/other-accessible socket dir (exit 2)" "2" "$?"
[[ -e "$UNSAFE/d.sock" ]] && ng "socket created in unsafe dir" || ok "no socket created in unsafe dir"
start_daemon
check "daemon socket mode" "600" "$(stat -c %a "$AGENT_DECIDE_SOCK")"
check "daemon lock file mode" "600" "$(stat -c %a "$AGENT_DECIDE_SOCK.lock")"

# ------------------------------------------------------------------
section "多重起動防止・stale ソケット掃除の安全性"
# ------------------------------------------------------------------
timeout 5 "${PY[@]}" "$DAEMON" --daemon >"$T/second.log" 2>&1
check "second --daemon exits 1 (already running)" "1" "$?"
grep -q "already running" "$T/second.log" && ok "second daemon reports already running" || ng "second daemon message: $(cat "$T/second.log")"
check "first daemon unaffected, same pid" "$DPID" "$("${PY[@]}" "$DAEMON" --status | jget pid)"
check "live socket not deleted by second start" "pong" "$("${PY[@]}" "$DAEMON" --ping)"
stop_daemon
[[ -e "$AGENT_DECIDE_SOCK" ]] && ng "socket not removed on --stop" || ok "socket removed on --stop"
echo precious >"$AGENT_DECIDE_SOCK"
timeout 5 "${PY[@]}" "$DAEMON" --daemon >/dev/null 2>&1
check "non-socket at socket path: daemon refuses (exit 2)" "2" "$?"
check "non-socket file preserved" "precious" "$(cat "$AGENT_DECIDE_SOCK")"
rm -f "$AGENT_DECIDE_SOCK"

# ------------------------------------------------------------------
section "--ping/--status/--stop と他プロセス保護"
# ------------------------------------------------------------------
"${PY[@]}" "$DAEMON" --ping >/dev/null 2>&1; check "--ping without daemon exits 1" "1" "$?"
"${PY[@]}" "$DAEMON" --status >/dev/null 2>&1; check "--status without daemon exits 1" "1" "$?"
sleep 300 & DECOY_PID=$!
echo "$DECOY_PID" >"$AGENT_DECIDE_SOCK.pid"
"${PY[@]}" "$DAEMON" --stop >/dev/null 2>&1; check "--stop without daemon exits 1" "1" "$?"
kill -0 "$DECOY_PID" 2>/dev/null && ok "--stop did not kill unrelated process (pidfile decoy)" || ng "--stop killed decoy process"
start_daemon
"${PY[@]}" "$DAEMON" --stop; check "--stop on running daemon exits 0" "0" "$?"
wait "$DPID" 2>/dev/null
check "daemon exited 0 after --stop" "0" "$?"
kill -0 "$DECOY_PID" 2>/dev/null && ok "decoy still alive after real --stop" || ng "decoy killed by --stop"
"${PY[@]}" "$DAEMON" --ping >/dev/null 2>&1; check "--ping after stop exits 1" "1" "$?"
"${PY[@]}" "$DAEMON" --bogus >/dev/null 2>&1; check "unknown option exits 64" "64" "$?"

# ------------------------------------------------------------------
section "shared.ts: callDecide (bun) はデーモンの有無・偽物で判定が変わらない"
# ------------------------------------------------------------------
if command -v bun >/dev/null 2>&1; then
    BUN_SCRIPT="$T/shared-check.ts"
    cat >"$BUN_SCRIPT" <<EOF
import { callDecide, clearDecideCache } from "$ROOT/agent/hooks/omp/lib/shared";
const req = JSON.parse(process.argv[2]);
clearDecideCache();
console.log(callDecide<any>("$ROOT", req, { decision: "FALLBACK" }).decision);
EOF
    check "ts callDecide: no daemon -> block" "block" "$(bun "$BUN_SCRIPT" "$REQ_RM" 2>&1)"
    start_daemon
    c5="$(req_count)"
    check "ts callDecide: daemon up -> block" "block" "$(bun "$BUN_SCRIPT" "$REQ_RM" 2>&1)"
    check "  (decide.py spawned by callDecide used the daemon)" "$((c5 + 2))" "$(req_count)"
    stop_daemon
    fake_listener "$FORGED"
    check "ts callDecide: forged listener cannot turn block into allow" "block" "$(bun "$BUN_SCRIPT" "$REQ_RM" 2>&1)"
    stop_fake
    rm -f "$AGENT_DECIDE_SOCK"
    (cd "$ROOT/agent/hooks/omp/lib" && bun hook-cache.test.ts >/dev/null 2>&1); check "existing hook-cache.test.ts passes" "0" "$?"
else
    echo "[SKIP] bun not found"
fi

# ------------------------------------------------------------------
section "後始末: 起動した子プロセスが残っていない"
# ------------------------------------------------------------------
sleep 0.3
left=0
for p in "${SPAWNED[@]:-}"; do
    if [[ -n "$p" && -r "/proc/$p/cmdline" ]] && tr '\0' ' ' <"/proc/$p/cmdline" | grep -q "decide_daemon.py\|FAKE_LISTENER_T8\|fake_daemon.py"; then
        left=$((left + 1)); echo "  leftover pid $p: $(tr '\0' ' ' </proc/$p/cmdline)"
    fi
done
check "no daemon/fake processes left from this run (before cleanup)" "0" "$left"

echo
if [[ "$total_fail" -eq 0 ]]; then echo "ALL PASS"; exit 0; fi
echo "$total_fail FAILED"; exit 1
