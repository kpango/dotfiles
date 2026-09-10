#!/usr/bin/env bash
# Antigravity PreToolUse Security Gate
#
# ルールデータは agent/security-rules.json (claude/agy/pi 共通) を読む。判定アルゴリズム自体は
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み(2026-09-03、claude/agy/piで3回
# 独立に再実装されていたロジックを1箇所化)。本ファイルはI/Oプロトコル変換のみを持つ薄いシム:
# stdin JSON(Antigravity/Claude系両方のスキーマを正規化)→ decide.pyへの正規化リクエスト →
# decide.pyの3値決定(allow/ask/block)をagy固有の2値(allow/deny、常にexit 0)へ変換する。
# agyにはclaudeのask相当の中間承認primitiveが無いため、tier=ask(decide.pyのask決定)も
# tier=block と同様にdenyへ倒す(agent/security-rules.jsonの$comment「最も保護範囲が広い版を
# 正典とする」方針に整合)。
set -euo pipefail

PAYLOAD=$(cat)

if ! command -v python3 &>/dev/null; then
    echo '{"decision":"allow"}'
    exit 0
fi

# agy/hooks は ~/.agy/hooks・~/.gemini/hooks へのsymlink(通常インストール経路)のため、
# `cd -P`(物理解決)でsymlinkを辿った実体ディレクトリを得てから`..`する
# (agent/hooks/claude/security-gate.sh と同じ理由、実測で確認済み)。docker/copy-install経路
# (symlinkでなく実体コピー)では実体ディレクトリがdotfilesリポジトリ外になるため、
# RULES_FILE が見つからず後述のPython側 fail-open(allow)になる既知の制約。この制約は
# agyのdocker/copy-install経路に限らず、claude/piのdocker/copy-install経路
# (claude/docker/install・pi/docker/installで実コピーされる場合)にも同様に当てはまる
# (2026-09-03 Phase 4.5 Round 2レビューで指摘、agy限定の記述はoverclaim — 実装は
# 3ツールとも同一のreadlink -f方式であり、実体コピーであればいずれもfail-openになる)。
# 追記(2026-09-03、agent-hooks-and-pi-agents-unificationミッション): ~/.agy/hooks・~/.gemini/hooksは
# agy/hooks/ と agent/hooks/agy/ の2ソースを合成したmerged directory(per-file symlink)であり、
# ディレクトリ自体はsymlinkではない — `readlink -f`でファイル自身のsymlinkを先に解決してから
# `dirname`する必要がある(GNU coreutils限定、実測で確認済み)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/security-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

if [[ ! -f "$RULES_FILE" ]] || [[ ! -f "$DECIDE" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

RULES_FILE="$RULES_FILE" DECIDE="$DECIDE" python3 -c '
import json, os, subprocess, sys

try:
    data = json.loads(sys.stdin.read() or "{}")
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

# Normalize tool name and args across AGY and Claude/Generic schemas
tool_call = data.get("toolCall", {})
tool_name = tool_call.get("name") or data.get("tool_name", "")
args = tool_call.get("args") or data.get("tool_input", {})

def deny(reason):
    print(json.dumps({"decision": "deny", "reason": reason}))
    sys.exit(0)

def allow():
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

def call_decide(request):
    try:
        proc = subprocess.run(
            [sys.executable, os.environ["DECIDE"]],
            input=json.dumps(request), capture_output=True, text=True, timeout=10,
        )
        return json.loads(proc.stdout)
    except Exception:
        # decide.py 自体が起動できない/クラッシュした場合も fail-open(致命的にしない)
        return {"decision": "allow"}

rules_file = os.environ["RULES_FILE"]

# ---------------------------------------------------------
# 1. Shell Command Checks (run_command / bash / run_shell_command)
# ---------------------------------------------------------
if tool_name in ("run_command", "bash", "run_shell_command"):
    cmd = args.get("CommandLine") or args.get("command", "")
    if cmd:
        # agy の git_reset_hard_protected_branch は cd/-C ターゲットを解決してから絶対化する
        # (旧agy実装には無かったチェックで、claude実装に倣い本統合で追随させた設計を維持)。
        result = call_decide({
            "family": "security_shell",
            "command": cmd,
            "cwd": os.getcwd(),
            "rules_file": rules_file,
            "resolve_command_target": True,
        })
        decision = result.get("decision", "allow")
        if decision in ("block", "ask"):
            reason = result.get("reason", "")
            deny(f"Security Gate: {reason}")

# ---------------------------------------------------------
# 2. File Modification Checks (write_to_file / replace_file_content / edit_file)
# ---------------------------------------------------------
if tool_name in ("write_to_file", "replace_file_content", "edit_file"):
    target = args.get("TargetFile") or args.get("file_path", "")
    if target:
        result = call_decide({
            "family": "security_write",
            "file_path": target,
            "cwd": os.getcwd(),
            "home": os.path.expanduser("~"),
            "rules_file": rules_file,
        })
        if result.get("decision") == "block":
            label = result.get("reason", "")
            deny(f"Security Gate: Blocked modification to protected/sensitive path ({label}): {target}")

# Default allow
allow()
' <<< "$PAYLOAD"
