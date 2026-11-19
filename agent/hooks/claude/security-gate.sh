#!/usr/bin/env bash
# PreToolUse:Bash hook — blocks catastrophic and irreversible commands
#
# ルールデータは agent/security-rules.json (claude/agy/omp 共通) を読む。判定アルゴリズムは
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み。本ファイルは I/O プロトコル変換と
# 単一 Python プロセスでの decide.dispatch 呼び出しを行う。
set -euo pipefail

INPUT=$(cat || true)
[[ -z "${INPUT//[[:space:]]/}" ]] && exit 0

HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/security-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

# ルールデータ/エンジン欠落時は fail-open(致命的にしない)。
[[ -f "$RULES_FILE" ]] || exit 0
[[ -f "$DECIDE" ]] || exit 0
command -v python3 &>/dev/null || exit 0

PY_SCRIPT='
import json, os, sys

sys.path.insert(0, os.path.dirname(os.environ["DECIDE"]))
import decide

try:
    data = json.loads(sys.stdin.read() or "{}")
    if not isinstance(data, dict):
        data = {}
except Exception:
    sys.exit(0)

tool_input = data.get("tool_input")
if not isinstance(tool_input, dict):
    sys.exit(0)
cmd = tool_input.get("command") or ""
if not isinstance(cmd, str) or not cmd:
    sys.exit(0)

result = decide.dispatch({
    "family": "security_shell",
    "command": cmd,
    "cwd": os.getcwd(),
    "rules_file": os.environ["RULES_FILE"],
    "resolve_command_target": False,
    "harness": "claude",
})
decision = result.get("decision", "allow")
reason = result.get("reason", "")

if decision == "block":
    print(json.dumps({"decision": "block", "reason": f"SECURITY GATE: {reason}"}))
    sys.exit(2)
if decision == "ask":
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": f"SECURITY GATE: {reason}",
        }
    }))
    sys.exit(0)
'

rc=0
if command -v timeout &>/dev/null; then
    RULES_FILE="$RULES_FILE" DECIDE="$DECIDE" timeout 10 python3 -c "$PY_SCRIPT" <<< "$INPUT" || rc=$?
else
    RULES_FILE="$RULES_FILE" DECIDE="$DECIDE" python3 -c "$PY_SCRIPT" <<< "$INPUT" || rc=$?
fi

[[ "$rc" -eq 2 ]] && exit 2
exit 0
