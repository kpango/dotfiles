#!/usr/bin/env bash
# Unified PreToolUse hook — Vald Laws 1-5 (Law 1: generated files, Law 2: direct
# toolchain invocation, Laws 3/4/5: panic/log.Fatal/discarded errors/stdlib imports in .go)
#
# ルールデータは agent/vald-law-rules.json (claude/agy/omp 共通) を読む。判定アルゴリズムは
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み。本ファイルは単一の stdin パースで
# Bash (Law 2) および Write|Edit|MultiEdit (Law 1 + Law 3/4/5) の3プロトコルを処理する薄いシム。
set -euo pipefail

PAYLOAD=$(cat || true)

if ! command -v python3 &>/dev/null; then
    exit 0
fi

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成したmerged directory
# (per-file symlink) であり、ディレクトリ自体はsymlinkではない — `readlink -f` でファイル自身の
# symlinkを先に解決してから `dirname` する必要がある (GNU coreutils限定、security-gate.sh と同様)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/vald-law-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

[[ -f "$RULES_FILE" ]] || exit 0
[[ -f "$DECIDE" ]] || exit 0

run_py() {
    if command -v timeout &>/dev/null; then
        timeout 10 python3 "$@"
    else
        python3 "$@"
    fi
}

RULES_FILE="$RULES_FILE" DECIDE="$DECIDE" run_py -c '
import json, os, sys

sys.path.insert(0, os.path.dirname(os.environ["DECIDE"]))
import decide

try:
    data = json.loads(sys.stdin.read() or "{}")
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

tool_name = data.get("tool_name") or ""
tool_input = data.get("tool_input")
if not isinstance(tool_input, dict):
    tool_input = {}

RULES_FILE = os.environ["RULES_FILE"]

def call_decide(request):
    try:
        return decide.dispatch(request)
    except Exception:
        return {"decision": "allow"}

# Vald Law 2 (PreToolUse:Bash, scope_mode="none", block -> exit 2)
command = (tool_input.get("command") or "").strip()
if command and tool_name in ("", "Bash"):
    result = call_decide({
        "family": "vald_law2",
        "command": command,
        "cwd": os.getcwd(),
        "vald_rules_file": RULES_FILE,
        "scope_mode": "none",
    })
    if result.get("decision") == "block":
        print(json.dumps({"decision": "block", "reason": result.get("reason") or "Vald Law 2 violation"}))
        sys.exit(2)

# Vald Law 1 & Laws 3/4/5 (PreToolUse:Write|Edit|MultiEdit)
file_path = tool_input.get("file_path") or ""
if file_path and tool_name in ("", "Write", "Edit", "MultiEdit"):
    law1 = call_decide({
        "family": "vald_law1",
        "file_path": file_path,
        "vald_rules_file": RULES_FILE,
    })
    if law1.get("decision") == "block":
        print(json.dumps({"decision": "block", "reason": law1.get("reason") or "Vald Law 1 violation"}))
        sys.exit(2)

    if file_path.endswith(".go"):
        content = ""
        if tool_name == "Write":
            content = tool_input.get("content") or ""
        elif tool_name == "Edit":
            content = tool_input.get("new_string") or ""
        elif tool_name == "MultiEdit":
            edits = tool_input.get("edits") or []
            if isinstance(edits, list):
                content = "\n".join(e.get("new_string") or "" for e in edits if isinstance(e, dict))
        elif tool_name == "":
            edits = tool_input.get("edits")
            if isinstance(edits, list):
                content = "\n".join(e.get("new_string") or "" for e in edits if isinstance(e, dict))
            else:
                content = tool_input.get("content") or tool_input.get("new_string") or ""

        if content:
            law345 = call_decide({
                "family": "vald_law345",
                "file_path": file_path,
                "content": content,
                "vald_rules_file": RULES_FILE,
                "scope_mode": "none",
            })
            decision = law345.get("decision")
            if decision == "block":
                print(json.dumps({"decision": "block", "reason": law345.get("reason") or "Vald Law 3/4/5 violation"}))
                sys.exit(2)
            if decision == "ask":
                violations = law345.get("violations") or []
                if violations:
                    reason = (
                        f"Vald Law violation(s) in {os.path.basename(file_path)}:\n"
                        + "\n".join(f"- {v}" for v in violations)
                    )
                    print(json.dumps({
                        "hookSpecificOutput": {
                            "hookEventName": "PreToolUse",
                            "permissionDecision": "ask",
                            "permissionDecisionReason": reason,
                        }
                    }))
                    sys.exit(0)

sys.exit(0)
' <<< "$PAYLOAD"
