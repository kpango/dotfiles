#!/usr/bin/env bash
# Antigravity PreToolUse RTK Command Rewriter
set -euo pipefail

PAYLOAD=$(cat)

if ! command -v rtk &>/dev/null; then
    echo '{"decision": "allow"}'
    exit 0
fi

python3 -c '
import json, subprocess, sys

try:
    data = json.loads(sys.stdin.read() or "{}")
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

tool_call = data.get("toolCall", {})
tool_name = tool_call.get("name") or data.get("tool_name", "")
args = tool_call.get("args") or data.get("tool_input", {})

if tool_name not in ("run_command", "bash", "run_shell_command"):
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

cmd = (args.get("CommandLine") or args.get("command", "")).strip()

if not cmd or cmd.startswith("rtk "):
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

try:
    res = subprocess.run(
        ["rtk", "rewrite", cmd],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=2
    )
    rewritten = res.stdout.strip()
    if rewritten and rewritten.startswith("rtk ") and rewritten != cmd:
        print(json.dumps({
            "decision": "allow",
            "overwrite": {
                "CommandLine": rewritten
            }
        }))
        sys.exit(0)
except Exception:
    pass

print(json.dumps({"decision": "allow"}))
' <<< "$PAYLOAD"
