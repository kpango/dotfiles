---
title: Pi 1.7.0 SOTA upgrades from pi-agent-improvement.pdf (30 techniques)
author: Kpango
date: 2026-11-27
branch: main
id: l-a5ae1d03
scope: repo
status: active
src: agent
touches:
  - ".github/workflows/agent-sync-verify.yaml"
  - ".github/workflows/update-model-catalog.yaml"
  - AGENTS.md
  - Makefile.d/install.mk
  - Makefile.d/update.mk
  - agent/AGENTS-agy-supplement.md
  - agent/AGENTS-pi-supplement.md
  - agent/AGENTS.md
  - agent/README.md
  - agent/ROUTING_CATALOG.md
---

## Decided

- Eliminated Harness Tax in Pi 1.7.0 by adding `exposure: "deferred"` to 31 specialized extension tools while keeping only 4 core tools (`edit`, `obs_recall`, `update_plan`, `subagent`) direct; enforced by `agent/harnesses/pi/extensions/lib/harness-tax.test.ts`.
- Added LangChain middleware guardrails via `agent/harnesses/pi/extensions/loop-guard.ts` (Read-Guard, 5-edit Doom-Loop, 3-fail detector, `PI_TURN_BUDGET=40`, `/env-context`) and upgraded `lsp-client.ts` with Delta Diagnostics, Honesty Contract, and Commit Guard.
- Added Reasoning Sandwich (`plan`/`implement`/`verify`) to `thinking-budget.ts`, `/branch-review` (`navigateTree` handoff) to `session-tree.ts`, `0600` JSONL session telemetry to `context-economy.ts`, and 2-consecutive-regression auto-rollback to `continual-harness.ts`.
- Consolidated 6 Agy Docker MCP servers (`k8s-native`, `k8s-cli`, `serena`, `cipher`, `github`, `slack`) into `agent/harnesses/pi/mcp.json` with `exposure: "codemode"` and `enabled: false`, and normalized `openai`/`antigravity-cli` aliases in `model-failover.ts`, `model-roles.ts`, and `subagents.ts`.

## Tried and ruled out

- Ruled out injecting `localContext` / per-turn diagnostics into `before_agent_start.systemPrompt` so Prefix KV-Cache stability is preserved across turns.
- Ruled out enabling the 6 Docker MCP servers by default (`enabled: true`) to keep startup fast and avoid Harness Tax on parallel `pi -p` subagent spawns.

## Watch out

- Pi 1.7.0 `mcp.json` `timeout` values are in **seconds** (e.g., `60`, `90`), whereas Agy `mcp_config.json` uses milliseconds (`60000`).
- All future custom extension tools should declare `exposure: "deferred"` unless needed as core loop primitives (total direct custom tools <= 5 enforced by `harness-tax.test.ts`).
