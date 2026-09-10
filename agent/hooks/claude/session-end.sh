#!/usr/bin/env bash
set -euo pipefail
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

# Try to read additional metadata from hook payload
INPUT=$(cat 2>/dev/null || true)
EXTRA=""
if [[ -n "$INPUT" ]]; then
    EXTRA=$(python3 -c "
import json, sys
d = json.load(sys.stdin)
tc = d.get('turn_count', d.get('message_count', ''))
out = []
if tc: out.append(f'turns={tc}')
print(' '.join(out))
" <<< "$INPUT" 2>/dev/null || true)
    [[ -n "$EXTRA" ]] && EXTRA=" $EXTRA"
fi

# Compute session duration
DURATION=""
START_FILE="${LOG_DIR}/.session-${SESSION_ID:0:8}.start"
if [[ -f "$START_FILE" ]]; then
    START_EPOCH=$(cat "$START_FILE" 2>/dev/null || true)
    if [[ -n "$START_EPOCH" ]]; then
        NOW_EPOCH=$(date +%s)
        ELAPSED=$(( NOW_EPOCH - START_EPOCH ))
        DURATION=" duration=${ELAPSED}s ($(( ELAPSED / 60 ))m$(( ELAPSED % 60 ))s)"
    fi
    rm -f "$START_FILE"
fi

# Get git repo/branch if available
GIT_INFO=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || true)
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    [[ -n "$REPO" ]] && GIT_INFO=" repo=${REPO}@${BRANCH}"
fi

echo "${TIMESTAMP} session-end${DURATION}${GIT_INFO}${EXTRA}" >> "${LOG_DIR}/sessions.log"
