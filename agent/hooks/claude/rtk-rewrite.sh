#!/usr/bin/env bash
set -euo pipefail

# Read hook payload once
payload="$(cat)"

# Fast-path check without spawning multiple jq processes if command is absent
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
if [[ -z "$cmd" ]]; then
  exit 0
fi

# Strictly whitelist high-volume test, build, and status commands only.
# NEVER rewrite cat/head/tail/read or return permissionDecision: "allow".
case "$cmd" in
  "go test"*|"cargo test"*|"cargo check"*|"cargo clippy"*|"cargo build"*|"npm test"*|"pnpm test"*|"bun test"*|"pytest"*|"git status"*|"git diff"*|"git log"*|"kubectl get"*|"kubectl logs"*|"docker ps"*|"gh pr checks"*|"make"*|"docker logs"*)
    if command -v rtk >/dev/null 2>&1; then
      rewritten="$(rtk rewrite "$cmd" 2>/dev/null || true)"
      if [[ -n "$rewritten" && "$rewritten" != "$cmd" ]]; then
        jq -n --arg cmd "$rewritten" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            updatedInput: {
              command: $cmd
            }
          }
        }'
      fi
    fi
    ;;
  *)
    exit 0
    ;;
esac
