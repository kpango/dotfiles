#!/usr/bin/env bash
# PreToolUse:Write|Edit — block writes to sensitive system paths
#
# ルールデータは agent/security-rules.json (claude/agy/omp 共通) の sensitive_write_path_rules を
# 読む。判定アルゴリズムは agent/scripts/hooks/rule_engine.py + decide.py へ統合済み。
# 本ファイルは I/O プロトコル変換と単一 Python プロセスでの decide.dispatch 呼び出しを行う。
set -euo pipefail

INPUT=$(cat || true)
[[ -z "${INPUT//[[:space:]]/}" ]] && exit 0

HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/security-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

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
file_path = tool_input.get("file_path") or ""
if not isinstance(file_path, str) or not file_path:
    sys.exit(0)

home = os.environ.get("HOME") or os.path.expanduser("~")
result = decide.dispatch({
    "family": "security_write",
    "file_path": file_path,
    "cwd": os.getcwd(),
    "home": home,
    "rules_file": os.environ["RULES_FILE"],
})

if result.get("decision") == "block":
    expanded = os.path.expanduser(file_path) if file_path.startswith("~") else file_path
    report_path = os.path.realpath(expanded)
    print(json.dumps({"decision": "block", "reason": f"Write to sensitive path blocked by security gate: {report_path}"}))
    sys.exit(2)
'

rc=0
if command -v timeout &>/dev/null; then
    RULES_FILE="$RULES_FILE" DECIDE="$DECIDE" timeout 10 python3 -c "$PY_SCRIPT" <<< "$INPUT" || rc=$?
else
    RULES_FILE="$RULES_FILE" DECIDE="$DECIDE" python3 -c "$PY_SCRIPT" <<< "$INPUT" || rc=$?
fi

[[ "$rc" -eq 2 ]] && exit 2
exit 0
