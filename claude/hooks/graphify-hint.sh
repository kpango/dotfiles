#!/usr/bin/env bash
# PreToolUse:Bash hook — route broad searches through graph-explore when a graph exists
set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

CMD=$(cat | jq -r '.tool_input.command // ""' 2>/dev/null || true)

case "$CMD" in
  *grep*|*rg\ *|*ripgrep*|*find\ *|*fd\ *|*ack\ *|*ag\ *)
    [[ -s graphify-out/graph.json ]] || exit 0
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "graph-explore: graphify-out/graph.json is available. When /dig is active, invoke the Skill tool with `graph-explore <current investigation goal>` before broad grep/find. It chooses CodeGraph or Graphify, caps returned context, and lists only direct reads needed for verification. Read GRAPH_REPORT.md only if scoped graph queries fail."
      }
    }'
    ;;
esac
