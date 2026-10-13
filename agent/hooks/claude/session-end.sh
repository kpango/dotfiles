#!/usr/bin/env bash
set -euo pipefail

# Read the hook's stdin JSON once (stdin can only be read once) before deriving
# SESSION_ID; the EXTRA-metadata block below reuses this same INPUT.
# session_id comes from the hook's stdin JSON (a documented common hook input field;
# the undocumented CLAUDE_SESSION_ID env var is not used). jq validates the JSON
# value: it must be a string made only of ASCII A-Z a-z 0-9 . _ - and not "." or ".."
# (the same allowed set as agent/scripts/jev/evidence_reducer.py's
# _sanitize_session_id), otherwise "unknown". Checking in jq rather than with bash
# `[[ =~ ]]` avoids two problems: bash range matching is locale-dependent, and $()
# strips a trailing newline before bash could see it. \A...\z is used because `$` also
# matches just before a final newline.
INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -rs '(.[0] | if type == "object" then .session_id else null end) as $s | if ($s | type) == "string" and ($s | test("\\A[A-Za-z0-9._-]+\\z")) and $s != "." and $s != ".." then $s else "unknown" end' 2>/dev/null || echo unknown)
SESSION_ID=${SESSION_ID:-unknown}
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

# Parse additional metadata (turn_count) from the payload already read above
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
