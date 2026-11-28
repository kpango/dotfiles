#!/usr/bin/env bash
# PreCompact hook — record session/git state before context compaction
# (previously also ran `graphify update .` here; removed with graphify's retirement)
set -euo pipefail

INPUT=$(cat || true)
SESSION_ID=$(python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('session_id', 'unknown'))
" <<< "$INPUT" 2>/dev/null || echo "unknown")

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

GIT_INFO=""
if git rev-parse --git-dir >/dev/null 2>&1; then
    REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || true)
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    GIT_INFO=" repo=${REPO}@${BRANCH} dirty=${DIRTY}"
fi

echo "${TIMESTAMP} pre-compact session=${SESSION_ID:0:8}${GIT_INFO}" >> "${LOG_DIR}/sessions.log"

python3 -c "import json; print(json.dumps({'continue': True}))"
