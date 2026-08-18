#!/usr/bin/env bash
# SessionStart hook — injects memory context at session start
set -euo pipefail

MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude/memory}"
MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log session start
LOG_DIR="$HOME/.claude/session-data"
mkdir -p "$LOG_DIR"
date +%s > "$LOG_DIR/.session-${SESSION_ID:0:8}.start" 2>/dev/null || true

# Build context from memory index + all individual memory files
CONTEXT=""
if [[ -f "$MEMORY_INDEX" ]]; then
    CONTEXT=$(head -200 "$MEMORY_INDEX" 2>/dev/null || true)
fi

# Append each memory file (sorted, MEMORY.md excluded)
FILE_COUNT=0
if [[ -d "$MEMORY_DIR" ]]; then
    while IFS= read -r -d '' file; do
        content=$(head -150 "$file" 2>/dev/null || true)
        [[ -n "$content" ]] && CONTEXT="${CONTEXT}

---
${content}"
        (( FILE_COUNT++ )) || true
    done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" ! -name "MEMORY.md" -print0 2>/dev/null | sort -z)
fi

# Also append any project-level CLAUDE.local.md if present
if [[ -f "CLAUDE.local.md" ]]; then
    LOCAL=$(cat "CLAUDE.local.md" 2>/dev/null || true)
    [[ -n "$LOCAL" ]] && CONTEXT="$CONTEXT

$LOCAL"
fi

CONTEXT_SIZE=${#CONTEXT}
echo "[$TIMESTAMP] Session started: ${SESSION_ID:0:8} cwd=$(pwd) memory=${FILE_COUNT}files/${CONTEXT_SIZE}bytes" >> "$LOG_DIR/sessions.log" 2>/dev/null || true

if command -v jq &>/dev/null && [[ -n "$CONTEXT" ]]; then
    CONTEXT_JSON=$(jq -Rs . <<< "$CONTEXT")
    printf '{"continue":true,"suppressOutput":true,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' "$CONTEXT_JSON"
else
    printf '{"continue":true,"suppressOutput":true}'
fi
