#!/usr/bin/env bash
# PreToolUse:Bash hook — suggest graphify when grep/find commands are detected
#
# 検出パターン・グラフパス候補・ヒント文言は agent/graphify-hint-config.json (claude/agy/pi 共通) を
# 読む。判定アルゴリズム自体は agent/scripts/hooks/rule_engine.py + decide.py へ統合済み
# (2026-09-03、claude/agy/piで3回独立に再実装されていたロジックを1箇所化)。本ファイルは
# I/Oプロトコル変換のみを持つ薄いシム。
set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

CMD=$(cat | jq -r '.tool_input.command // ""' 2>/dev/null || true)
[[ -z "$CMD" ]] && exit 0

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成したmerged directory
# (per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
CONFIG_FILE="$ROOT/agent/graphify-hint-config.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

[[ -f "$CONFIG_FILE" ]] || exit 0
[[ -f "$DECIDE" ]] || exit 0
command -v python3 &>/dev/null || exit 0

# グラフパス候補の探索基準は旧実装どおり hook プロセスの cwd 単一。
REQUEST=$(jq -n --arg cmd "$CMD" --arg cwd "$(pwd)" --arg config "$CONFIG_FILE" \
    '{family: "graphify_hint", command: $cmd, config_file: $config, search_bases: [$cwd]}')

if command -v timeout &>/dev/null; then
    RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || exit 0
else
    RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || exit 0
fi

HINT=$(echo "$RESULT" | jq -r '.hint // empty' 2>/dev/null || echo "")
[[ -z "$HINT" ]] && exit 0

jq -n --arg msg "$HINT" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $msg
  }
}'
