#!/usr/bin/env bash
# PreToolUse:Write|Edit hook — Vald Law 1: no direct edits to generated files
#
# ルールデータは agent/vald-law-rules.json (claude/agy/pi 共通) を読む。判定アルゴリズムは
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み(2026-09-03)。本ファイルは
# I/Oプロトコル変換のみを持つ薄いシム。
set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat || true)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
[[ -z "$FILE_PATH" ]] && exit 0

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成したmerged directory
# (per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/vald-law-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

[[ -f "$RULES_FILE" ]] || exit 0
[[ -f "$DECIDE" ]] || exit 0
command -v python3 &>/dev/null || exit 0

REQUEST=$(jq -n --arg path "$FILE_PATH" --arg rules "$RULES_FILE" \
    '{family: "vald_law1", file_path: $path, vald_rules_file: $rules}')

if command -v timeout &>/dev/null; then
    RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || exit 0
else
    RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || exit 0
fi
DECISION=$(echo "$RESULT" | jq -r '.decision // "allow"' 2>/dev/null || echo "allow")

if [[ "$DECISION" == "block" ]]; then
    REASON=$(echo "$RESULT" | jq -r '.reason // "Vald Law 1 violation"' 2>/dev/null || echo "Vald Law 1 violation")
    jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
    exit 2
fi

exit 0
