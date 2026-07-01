#!/usr/bin/env bash
# PreToolUse:Bash hook — blocks catastrophic and irreversible commands
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -z "$COMMAND" ]] && exit 0

block() {
    jq -n --arg reason "SECURITY GATE: $1" '{"decision":"block","reason":$reason}' 2>/dev/null || \
        printf '{"decision":"block","reason":"SECURITY GATE: %s"}\n' "$1"
    exit 2
}

# Catastrophic patterns — always block (exit 2)
CATASTROPHIC=(
    'rm -rf /'
    'rm -rf ~$'
    'rm -fr /'
    'rm -fr ~$'
    ':(){ :|: }; :'
    'dd if=/dev/zero of=/dev/sd'
    'dd if=/dev/zero of=/dev/nvme'
    'dd if=/dev/zero of=/dev/vd'
    '> /dev/sda'
    '> /dev/nvme'
    'mkfs\..*\/dev\/'
    'shred.*\/dev\/'
)

for pattern in "${CATASTROPHIC[@]}"; do
    if grep -qE "$pattern" <<< "$COMMAND" 2>/dev/null; then
        block "Catastrophic command blocked: $pattern"
    fi
done

# Force-push to protected branches — block
if grep -qE 'git push.*(--force|-f).*(origin/)?(main|master|release|production)' <<< "$COMMAND"; then
    block "Force push to protected branch blocked"
fi

# Pipe-shell execution (curl/wget/echo/base64 piped to shell) — block
if grep -qE '(curl|wget)\b.*\|\s*(sudo\s+)?(sh|bash|zsh|fish|dash)\b' <<< "$COMMAND"; then
    block "Pipe-to-shell execution blocked"
fi
if grep -qE '(base64\s+-d|base64\s+--decode|echo\b).*\|\s*(sudo\s+)?(sh|bash|zsh|dash)\b' <<< "$COMMAND"; then
    block "Obfuscated pipe-to-shell execution blocked"
fi

# Recursive chmod 777 on broad paths — block
if grep -qE 'chmod\s+-R\s+0?777\s+(/|~|/home|/etc|/usr)' <<< "$COMMAND"; then
    block "Recursive chmod 777 on system path blocked"
fi

# git clean with -fdx (nukes untracked + gitignored files) — block
if grep -qE 'git clean\b.*-[a-zA-Z]*f[a-zA-Z]*[dx]' <<< "$COMMAND"; then
    block "git clean -f[dx] blocked — use -n (dry-run) first"
fi

# kubectl delete / helm uninstall on production namespaces — block
PROD_NS_PATTERN='(prod|production|vald-prod|vald-production)'
if grep -qE "kubectl delete.+-n\s*${PROD_NS_PATTERN}" <<< "$COMMAND"; then
    block "kubectl delete on production namespace blocked"
fi
if grep -qE "kubectl delete namespace\s+${PROD_NS_PATTERN}" <<< "$COMMAND"; then
    block "kubectl delete namespace on production blocked"
fi
if grep -qE "(helm uninstall|helm delete).+-n\s*${PROD_NS_PATTERN}" <<< "$COMMAND"; then
    block "helm uninstall on production namespace blocked"
fi

# git reset --hard on main/master without explicit worktree context
if grep -qE 'git reset --hard HEAD~[0-9]+' <<< "$COMMAND" && \
   ! grep -q 'worktree' <<< "$COMMAND"; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
        block "git reset --hard on protected branch blocked"
    fi
fi

exit 0
