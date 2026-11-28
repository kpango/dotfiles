---
title: "Pi 1.7.0 DeepResearch SOTA Phase 2 (LCM, RRSI, Self-Org, Hashline CAS Undo)"
author: Kpango
date: 2026-11-28
branch: main
id: l-721e0194
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

- Added Lossless Context Management (`lcm-core.ts` / `lcm-context.ts`) with `0700`/`0600` JSONL immutable store + SHA-256 `lcm-<10hex>` IDs, 3-level escalating convergence, and Subtask Stack Machine (`subtask_frame`, `lcm_recall` as `exposure: "deferred"` to preserve `direct <= 5`).
- Added RRSI regularization (`--rrsi`, leakage critic, annealed diff budget, bootstrap noise floor, `--prune-audit`) and AHE change-manifest falsification (`evaluate_ahe_manifest`) to `agent/scripts/evolve/harness2-offline.py`.
- Added 5-topology self-organizing selector (`selectSelfOrganizingTopology`) and time-decayed `StigmergyBoard` to `subagent-mesh-core.ts` / `subagent-mesh.ts`.
- Added unique `+/-15` line auto-rebase + 32-entry `CasUndoStore` (`/edit-undo`) to `hashline-core.ts` / `hashline-edit.ts`, and read-only `resolveModelFamilyGuidance` (`/thinking-budget profile`) to `thinking-budget.ts`.

## Tried and ruled out

- Mutating `before_agent_start.systemPrompt` per turn for model-family guidance was ruled out because it invalidates Prefix KV-Cache; guidance is exposed read-only via command/helper instead.
- Registering `subtask_frame` or `lcm_recall` as direct tools was ruled out because `harness-tax.test.ts` enforces `direct <= 5` (currently `4` direct, `33` deferred).

## Watch out

- Always run `make pi/install` after adding a new file under `agent/harnesses/pi/extensions/` or `lib/` so per-file symlinks in `~/.pi/agent/extensions/` are created, and keep `validate-harness.sh` lists updated.
- Ambiguous rebased lines inside the `+/-15` window must fail closed (`findUniqueRebasedLine` returns `null` when multiple matches exist).
