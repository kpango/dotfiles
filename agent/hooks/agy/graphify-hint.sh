#!/usr/bin/env bash
# Antigravity PreToolUse Graphify Knowledge Graph Assistant
#
# 検出パターン・グラフパス候補・ヒント文言は agent/graphify-hint-config.json (claude/agy/pi 共通) を
# 読む。判定アルゴリズム自体は agent/scripts/hooks/rule_engine.py + decide.py へ統合済み
# (2026-09-03)。本ファイルはI/Oプロトコル変換のみを持つ薄いシム。
set -euo pipefail

PAYLOAD=$(cat)

if ! command -v python3 &>/dev/null; then
    echo '{"decision":"allow"}'
    exit 0
fi

# ~/.agy/hooks・~/.gemini/hooks は agy/hooks/ と agent/hooks/agy/ の2ソースを合成したmerged
# directory(per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
CONFIG_FILE="$ROOT/agent/graphify-hint-config.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

if [[ ! -f "$CONFIG_FILE" ]] || [[ ! -f "$DECIDE" ]]; then
    echo '{"decision":"allow"}'
    exit 0
fi

CONFIG_FILE="$CONFIG_FILE" DECIDE="$DECIDE" python3 -c '
import json, os, subprocess, sys

try:
    data = json.loads(sys.stdin.read() or "{}")
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

tool_call = data.get("toolCall", {})
tool_name = tool_call.get("name") or data.get("tool_name", "")
args = tool_call.get("args") or data.get("tool_input", {})

def allow(reason=None):
    out = {"decision": "allow"}
    if reason:
        out["reason"] = reason
    print(json.dumps(out))
    sys.exit(0)

if tool_name not in ("run_command", "bash", "run_shell_command"):
    allow()

cmd = args.get("CommandLine") or args.get("command", "")
if not cmd:
    allow()

workspaces = data.get("workspacePaths", [os.getcwd()])
try:
    proc = subprocess.run(
        [sys.executable, os.environ["DECIDE"]],
        input=json.dumps({
            "family": "graphify_hint",
            "command": cmd,
            "config_file": os.environ["CONFIG_FILE"],
            "search_bases": workspaces,
        }),
        capture_output=True, text=True, timeout=10,
    )
    result = json.loads(proc.stdout)
except Exception:
    # decide.py 自体が起動できない/クラッシュした場合も fail-open(致命的にしない)
    allow()

allow(result.get("hint"))
' <<< "$PAYLOAD"
