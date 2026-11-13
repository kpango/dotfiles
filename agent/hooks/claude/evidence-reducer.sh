#!/usr/bin/env bash
# PostToolUse:Bash hook — evidence reducer (CONTEXT.md "ai-env-deepresearch-overhaul",
# T11 / I-5). Compresses large stdout/stderr into head+tail+critical(+Laya-ranked)
# lines, replacing Bash's tool_response via `updatedToolOutput` (Claude Code 2.1.281+;
# CONTEXT.md line 298-300, citing code.claude.com/docs/en/hooks: "Prefer
# updatedToolOutput, which works for all tools"; value must match the tool's own
# output shape or is ignored). The full, unreduced text is always saved first
# (agent/scripts/jev/evidence_reducer.py's `_save_full_text`, mode 0600) before any
# line is dropped.
#
# Claude-only: Reducer relies on updatedToolOutput, which agy/pi do not have
# (CONTEXT.md 責務境界) -- this shim is intentionally not mirrored under
# agent/hooks/agy/ or agent/hooks/pi/.
#
# Fail-open: ANY failure in this shim (jq/python3 missing, evidence_reducer.py
# missing, non-zero exit, malformed JSON) falls through to `exit 0` with NO stdout,
# which Claude Code treats as "do not modify tool output" -- the original Bash
# output is delivered to the transcript exactly as produced, unreduced.
set -euo pipefail

INPUT=$(cat)

command -v jq &>/dev/null || exit 0
command -v python3 &>/dev/null || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

# claude/hooks is a merged directory (per-file symlink from both
# agent/harnesses/claude/hooks/ and agent/hooks/claude/) -- resolve this file's own
# symlink with `readlink -f` before `dirname`, the same pattern security-gate.sh
# already uses (see that file's own comment for why a naive `cd -P $(dirname
# $BASH_SOURCE)` is not sufficient once the directory itself stopped being a
# single symlink).
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
REDUCER="$ROOT/agent/scripts/jev/evidence_reducer.py"
[[ -f "$REDUCER" ]] || exit 0

# Read from the hook's own input JSON, not an env var: the hooks reference documents
# `session_id` as a common input field and does not document CLAUDE_SESSION_ID (it is
# also absent from this environment), so the env-var read fell back to "unknown" and
# every saved-evidence file landed under .../evidence-reducer/unknown/ regardless of
# the real session. Same `jq -r '.session_id // "unknown"'` pattern as
# agent/hooks/claude/swarm-stop-verify.sh.
#
# This line does not check the value itself. Which values are used is decided
# downstream by agent/scripts/jev/evidence_reducer.py's `_sanitize_session_id()`
# (lines 240-249), which turns rejected values such as "../x", "." and ".." into
# "unknown" before the value is used in a save-directory path.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
REQUEST=$(echo "$INPUT" | jq --arg sid "$SESSION_ID" \
    '{session_id: $sid, tool_response: (.tool_response // {})}')

if command -v timeout &>/dev/null; then
    RESULT=$(echo "$REQUEST" | timeout 5 python3 "$REDUCER" 2>/dev/null) || exit 0
else
    RESULT=$(echo "$REQUEST" | python3 "$REDUCER" 2>/dev/null) || exit 0
fi

CHANGED=$(echo "$RESULT" | jq -r '.changed // false' 2>/dev/null || echo "false")
[[ "$CHANGED" == "true" ]] || exit 0

echo "$RESULT" | jq -c '{hookSpecificOutput: {hookEventName: "PostToolUse", updatedToolOutput: .tool_response}}' 2>/dev/null || exit 0
exit 0
