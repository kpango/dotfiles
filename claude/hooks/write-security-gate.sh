#!/usr/bin/env bash
# PreToolUse:Write|Edit — block writes to sensitive system paths
set -euo pipefail

INPUT=$(cat || true)

if ! command -v jq &>/dev/null; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0

# Expand ~ to home directory
FILE_PATH="${FILE_PATH/#\~/$HOME}"

BLOCKED_PATTERNS=(
    "^${HOME}/.ssh/"
    "^${HOME}/.gnupg/"
    "^${HOME}/.aws/"
    "^${HOME}/.kube/config$"
    "^${HOME}/.netrc$"
    "^${HOME}/.cargo/credentials"
    "^${HOME}/.npmrc$"
    "^/etc/"
    "^/boot/"
    "^/dev/"
    "^/proc/"
    "^/sys/"
    "^/usr/lib/systemd/system/"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$FILE_PATH" | grep -qE "$pattern"; then
        jq -n --arg path "$FILE_PATH" \
            '{"decision":"block","reason":("Write to sensitive path blocked by security gate: "+$path)}'
        exit 2
    fi
done

exit 0
