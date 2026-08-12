#!/usr/bin/env bash
# PreToolUse:Bash hook — suggest graphify when grep/find commands are detected
set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

CMD=$(cat | jq -r '.tool_input.command // ""' 2>/dev/null || true)

case "$CMD" in
  *grep*|*rg\ *|*ripgrep*|*find\ *|*fd\ *|*ack\ *|*ag\ *)
    [[ -f graphify-out/graph.json ]] || exit 0
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "graphify: knowledge graph at graphify-out/. For focused questions, run `graphify query \"<question>\"` (scoped subgraph, usually much smaller than GRAPH_REPORT.md) instead of grepping raw files. Read GRAPH_REPORT.md only for broad architecture context."
      }
    }'
    ;;
esac
