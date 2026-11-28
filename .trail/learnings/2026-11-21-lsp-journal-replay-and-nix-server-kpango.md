---
title: LSP journal replay and nix server choice
author: Kpango
date: 2026-11-21
branch: main
id: l-17c6a82f
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/omp/SYSTEM.md
  - agent/harnesses/omp/extensions/lib/session-journal.test.ts
  - agent/harnesses/omp/extensions/session-journal.ts
  - agent/harnesses/omp/lsp.yml
---

## Decided

- SoL-Pi session journal replays `lsp` only for OMP's own `LSP_READONLY_ACTIONS` (diagnostics, definition, type_definition, implementation, references, hover, symbols, status, capabilities). `reload` is write-tier upstream, so replaying its cached result would skip a config reload; `rename`, `rename_file`, `code_actions` stay non-replayable for the same reason.
- `agent/harnesses/omp/lsp.yml` no longer declares `nixd`. OMP merges the user file over `src/lsp/defaults.json`, which already carries `nixd` then `nil` for `.nix`; the override only pinned a host binary that is not installed (the dev container installs it in `dockers/nix.Dockerfile`), and the host silently used `nil` anyway.

## Tried and ruled out

- Declaring `nil` explicitly in lsp.yml: no-op, nil is already in the defaults with identical root markers.
- Keeping `nixd` as intent: on the host it never resolves, so the declared server was a lie and `lsp status` reports it unresolved; the container resolves nixd through the defaults.

## Watch out

- `lsp status`/`diagnostics` replays hit the 30s read TTL: an identical call inside 30s returns the cached result. Vary a param to force a live query.
- Server preference is config-order over the merged map (defaults first, overrides appended), so adding a server entry does not reorder candidates.
