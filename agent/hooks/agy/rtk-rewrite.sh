#!/usr/bin/env bash
# Antigravity PreToolUse RTK Command Rewriter
set -euo pipefail

# Read hook payload once
payload="$(cat || true)"
if [[ -z "${payload//[[:space:]]/}" ]]; then
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Extract schema type and command in a single jq invocation
parsed="$(printf '%s' "$payload" | jq -r '
  if (.toolCall | type) == "object" then
    "AGY\u001f" + (.toolCall.args.CommandLine // .toolCall.args.command // "")
  else
    "CLAUDE\u001f" + (.tool_input.command // .command // "")
  end
' 2>/dev/null || true)"

schema="${parsed%%$'\x1f'*}"
cmd="${parsed#*$'\x1f'}"

if [[ -z "$cmd" ]]; then
    if [[ "$schema" == "AGY" ]]; then
        printf '{"decision":"allow"}\n'
    fi
    exit 0
fi

# Strictly whitelist high-volume test, build, and status commands only.
# NEVER rewrite cat/head/tail/read or return permissionDecision: "allow".
case "$cmd" in
    "go test"*|"cargo test"*|"cargo check"*|"cargo clippy"*|"npm test"*|"pnpm test"*|"bun test"*|"pytest"*|"git status"*|"git diff"*|"git log"*|"kubectl get"*|"kubectl logs"*|"docker ps"*|"gh pr checks"*)
        if command -v rtk >/dev/null 2>&1; then
            rewritten="$(rtk rewrite "$cmd" 2>/dev/null || true)"
            if [[ -n "$rewritten" && "$rewritten" != "$cmd" ]]; then
                if [[ "$schema" == "AGY" ]]; then
                    jq -cn --arg cmd "$rewritten" '{"decision":"allow","overwrite":{"CommandLine":$cmd}}'
                else
                    jq -n --arg cmd "$rewritten" '{
                      hookSpecificOutput: {
                        hookEventName: "PreToolUse",
                        updatedInput: {
                          command: $cmd
                        }
                      }
                    }'
                fi
                exit 0
            fi
        fi
        ;;
esac

if [[ "$schema" == "AGY" ]]; then
    printf '{"decision":"allow"}\n'
fi
exit 0
