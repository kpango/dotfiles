---
title: EPR provider path was dead code behind a green suite
author: Kpango
date: 2026-11-21
branch: main
id: l-35523f45
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/omp/extensions/sol-pi.ts
---

## Decided

SoL-Pi EPR provider path now truly executes: `reducerPromptBody` (imported name) replaced the undefined `promptBody`, and the unverifiable-receipt branch records its fallback reason through `logFallback` instead of calling the journal object.

## Tried and ruled out

Trusting a green `bun test`: the preload stub for `@oh-my-pi/pi-ai` returned a deep proxy, so every provider call "failed" in a way the tests expected. The suite stayed green while the applied-receipt path was unreachable in production.

## Watch out

Bun transpiles without typechecking, so a bare undefined identifier only fails at runtime. `bunx tsc --noEmit ... | grep -E "TS2304|TS2552"` over extension entrypoints catches this class (ignore `__dirname`, `setImmediate`, `Bun`). Add a provider seam (globalThis in the test preload) before asserting any branch downstream of `completeSimple`.
