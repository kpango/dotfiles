#!/usr/bin/env bash
# SessionStart hook — injects memory context at session start
#
# メモリdir/ローカルoverrideファイルの走査・合成ロジックは agent/scripts/hooks/memory_context.py +
# decide.py へ統合済み(2026-09-03、agent/hooks/agy/session-start.shと独立に再実装されていたロジックを
# 1箇所化)。本ファイルはI/Oプロトコル変換(セッションログ書き込み・hookSpecificOutput整形)のみ。
set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude/memory}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log session start
LOG_DIR="$HOME/.claude/session-data"
mkdir -p "$LOG_DIR"
date +%s > "$LOG_DIR/.session-${SESSION_ID:0:8}.start" 2>/dev/null || true

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成したmerged directory
# (per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

CONTEXT=""
FILE_COUNT=0
if [[ -f "$DECIDE" ]] && command -v python3 &>/dev/null && command -v jq &>/dev/null; then
    REQUEST=$(jq -n --arg dir "$MEMORY_DIR" --arg cwd "$(pwd)" \
        '{family: "memory_context", memory_dirs: [$dir], local_files: ["CLAUDE.local.md"], cwd: $cwd,
          index_head: 200, topic_head: 150, local_head: null,
          multi_dir_labels: false, local_all_matches: false}')
    if command -v timeout &>/dev/null; then
        RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || RESULT=""
    else
        RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || RESULT=""
    fi
    if [[ -n "$RESULT" ]]; then
        CONTEXT=$(echo "$RESULT" | jq -r '.context // ""' 2>/dev/null || echo "")
        FILE_COUNT=$(echo "$RESULT" | jq -r '.file_count // 0' 2>/dev/null || echo 0)
    fi
fi

CONTEXT_SIZE=${#CONTEXT}
echo "[$TIMESTAMP] Session started: ${SESSION_ID:0:8} cwd=$(pwd) memory=${FILE_COUNT}files/${CONTEXT_SIZE}bytes" >> "$LOG_DIR/sessions.log" 2>/dev/null || true

if command -v jq &>/dev/null && [[ -n "$CONTEXT" ]]; then
    CONTEXT_JSON=$(jq -Rs . <<< "$CONTEXT")
    printf '{"continue":true,"suppressOutput":true,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' "$CONTEXT_JSON"
else
    printf '{"continue":true,"suppressOutput":true}'
fi
