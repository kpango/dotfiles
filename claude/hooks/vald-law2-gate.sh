#!/usr/bin/env bash
# PreToolUse:Bash hook — Vald Law 2: no direct toolchain invocation
set -euo pipefail

INPUT=$(cat || true)

if ! command -v jq &>/dev/null; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -z "$COMMAND" ]] && exit 0

# Blocked patterns with their make alternatives
declare -A BLOCKED=(
    ['^go (build|run|install)\b']='make build (or the appropriate make target)'
    ['^cargo (build|run|install)\b']='make build/rust (or the appropriate make target)'
    ['^kubectl apply\b']='make k8s/vald/deploy HELM_VALUES=...'
    ['^helm (install|upgrade|uninstall|delete)\b']='make k8s/vald/deploy or helm/install make targets'
)

for pattern in "${!BLOCKED[@]}"; do
    if echo "$COMMAND" | grep -qE "$pattern" 2>/dev/null; then
        ALT="${BLOCKED[$pattern]}"
        python3 -c "
import json, sys
msg = {
    'decision': 'block',
    'reason': f'Vald Law 2: Direct toolchain invocation forbidden. Use: {sys.argv[1]}'
}
print(json.dumps(msg))
" "$ALT"
        exit 2
    fi
done

exit 0
