#!/usr/bin/env bash
set -euo pipefail

CONTEXT_PARTS=()

# Add git branch and last commit if in a git repo
if git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
    LAST_COMMIT=$(git log --oneline -1 2>/dev/null || true)
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)
    CONTEXT_PARTS+=("Repo: ${REPO} (branch: ${BRANCH})")
    [[ -n "$LAST_COMMIT" ]] && CONTEXT_PARTS+=("Last commit: ${LAST_COMMIT}")
    [[ "$DIRTY" -gt 0 ]] && CONTEXT_PARTS+=("Uncommitted changes: ${DIRTY} file(s)")
    [[ "$GIT_DIR" != "${WORKTREE_ROOT}/.git" && "$GIT_DIR" != ".git" ]] \
        && CONTEXT_PARTS+=("Note: running in a git worktree")
    CWD_REL=$(git rev-parse --show-prefix 2>/dev/null | sed 's|/$||' || true)
    [[ -n "$CWD_REL" ]] && CONTEXT_PARTS+=("CWD: ${CWD_REL}")
fi

# Add tmux session/window if running inside tmux
if [[ -n "${TMUX:-}" ]]; then
    TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || true)
    TMUX_WINDOW=$(tmux display-message -p '#I:#W' 2>/dev/null || true)
    [[ -n "$TMUX_SESSION" ]] && CONTEXT_PARTS+=("Tmux: ${TMUX_SESSION} / ${TMUX_WINDOW}")
fi

# Add current date/time
CONTEXT_PARTS+=("Date: $(date '+%Y-%m-%d %H:%M %Z')")

if [ ${#CONTEXT_PARTS[@]} -gt 0 ]; then
    CONTEXT=$(printf '%s\n' "${CONTEXT_PARTS[@]}")
    jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
fi
