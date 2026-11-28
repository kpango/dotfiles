---
title: OMP to Pi 1.7.0 migration and Google AI Ultra native auth tracking
author: Kpango
date: 2026-11-27
branch: main
id: l-c549c9d5
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

- Replaced OMP with `@earendil-works/pi-coding-agent@1.7.0` across `agent/harnesses/pi/`, `agent/hooks/pi/`, `Makefile.d/install.mk`, Nix, systemd user units, and Dockerfiles, keeping `~/.omp` untouched as backup.
- Replaced OMP native features with 5 self-hosted TypeScript extensions under `agent/harnesses/pi/extensions/`: `hashline-edit.ts`, `lsp-client.ts`, `dap-client.ts`, `ttsr-guard.ts`, and `model-roles.ts`.
- Integrated Pstack principles directly into `agent/SWARM.md`, `swarm-loop`/`swarm-graph`/`swarm-architect`/`ponytail-patterns` skills, `lib/evidence-ledger.ts`, `lib/ponytail-guard-core.ts`, and `adversarial-reviewer.ts`.
- Routed interactive `agy acp` / `/model` Antigravity models via `npm:@estebanforge/pi-antigravity-bridge@1.16.0` in `agent/harnesses/pi/settings.json` (`packages`) and explicit CLI delegation via `bridge-antigravity.ts` (`/agy-cli`, tool `antigravity_cli`). Track upstream native Google AI Ultra auth in `agent/context/pi-google-ai-ultra-tracking.md`.

## Tried and ruled out

- Ruled out `@piex-dev/{hashline,lsp,dap}` and `pi-pstack-native` to avoid external dependency bloat and preserve repo-native SWARM/security gates.
- Ruled out registering tool `"antigravity"` in `bridge-antigravity.ts` because `@estebanforge/pi-antigravity-bridge@1.16.0` owns `"antigravity"` and `/agy`.

## Watch out

- Pi 1.7.0 loads `.ts` extensions via jiti where `import.meta.dir` is `undefined`; always resolve relative directories with a `MODULE_DIR` fallback to `__dirname` or `fileURLToPath(import.meta.url)` (`dap-core.ts`, `lsp-core.ts`, `model-roles-core.ts`, `repl-context-core.ts`, `sol-pi-core.ts`).
- Do not call action methods such as `pi.setLabel()` during top-level extension registration (`bridge-hermes.ts`), or Pi 1.7.0 throws `Extension runtime not initialized`.
- `dap.json` uses `"connectMode": "socket"|"stdio"`, not `"transport"`, and `models.json` `opencode-go` omits `apiKey` (resolved via OAuth/auth storage) while `ollama` sets `"apiKey": "ollama"`.
