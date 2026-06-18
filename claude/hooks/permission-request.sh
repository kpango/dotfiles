#!/usr/bin/env bash
# PermissionRequest hook — auto-approve safe read-only tool calls, log others
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
RULE=$(echo "$INPUT" | jq -r '.rule // ""' 2>/dev/null || echo "")

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

allow() {
    printf '{"decision":"allow","reason":"%s"}\n' "$1"
    echo "${TIMESTAMP} permission-request: tool=${TOOL} rule=${RULE} outcome=allow" >> "${LOG_DIR}/sessions.log" || true
    exit 0
}

# If jq is unavailable, try grep-based fallback for tool extraction
if [[ "$TOOL" == "unknown" ]]; then
    TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' 2>/dev/null || echo "unknown")
fi

# Auto-approve for known safe read-only patterns
case "${TOOL}" in
    Read|Glob|Grep|LS)
        allow "read-only tool auto-approved"
        ;;
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
        # Fallback: grep-based command extraction when jq unavailable
        if [[ -z "$CMD" ]]; then
            CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' 2>/dev/null || true)
        fi
        # If command extraction failed entirely, allow (security-gate.sh is the real boundary)
        if [[ -z "$CMD" ]]; then
            allow "command extraction unavailable — security-gate.sh provides primary protection"
        fi
        if grep -qE \
            '^(git (status|log|diff|show|branch|tag|remote -v|describe|rev-parse)|'\
'ls\b|ll\b|la\b|cat\b|head\b|tail\b|'\
'grep\b|rg\b|find\b|wc\b|stat\b|file\b|du\b|df\b|'\
'which\b|command -v\b|type\b|echo\b|printf\b|pwd\b|'\
'python3 -m json\.tool\b|jq -r?\b|'\
'go (version|env|list)\b|cargo (--version|metadata)\b|'\
'codegraph (status|files|query|hook status)\b|'\
'graphify (query|path|explain|hook status)\b|'\
'pass show\b|'\
'paru (-Ss|-Qi|-Si|-Sl|-Ql|-Qu|-Q)\b|'\
'cargo fmt --check\b|'\
'tmux (list-sessions|list-windows|list-panes|show-options|display-message)\b|'\
'make (proto/(all|go|swagger)|license|format|lint|test|test/rust|build|update|init|help)\b|'\
'buf (lint|breaking|format|check)\b|'\
'kubectl (get|describe|logs|top|explain|api-resources|version)\b|'\
'docker (ps|logs|inspect|images|stats|version|info)\b|'\
'helm (list|status|get|version|history|show)\b|'\
'systemctl (status|is-active|is-enabled|list-units|list-timers)\b|'\
'journalctl\b|'\
'rtk (gain|discover|--version)\b|'\
'cargo (check|clippy|audit|tree)\b|'\
'rustup (show|target|toolchain)\b|'\
'npm (list|ls|outdated|audit)\b)' <<< "$CMD"; then
            allow "read-only bash command auto-approved"
        fi
        ;;
esac

# Pass through — let Claude Code handle the permission dialog
echo "${TIMESTAMP} permission-request: tool=${TOOL} rule=${RULE} outcome=passthrough" >> "${LOG_DIR}/sessions.log" || true
exit 0
