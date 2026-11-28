---
title: OMP config silently drops unregistered keys; session_stop block bypasses the host continuation cap
author: Kpango
date: 2026-11-21
branch: swarm-mission/pi-techniques-30-20261122-015240
id: l-7064e978
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/agy/hooks/hooks.json
  - agent/harnesses/omp/config.yml
  - agent/harnesses/omp/extensions/lib/stop-verify.test.ts
  - agent/harnesses/omp/extensions/stop-verify.ts
  - agent/scripts/test-omp-extensions.sh
  - agent/scripts/sync-verify.sh
---

## Decided

- `agent/harnesses/omp/config.yml` must use registered setting ids: `memory.backend` (not `memory.enabled`), `disassembler.backend` (not `disassembler.enabled`), and `<tool>.enabled` (not `tools.disabled`). Nagoya: host 19.0.1 `config/settings.ts` only throws on unknown keys for constructor overrides; YAML keys are silently ignored.
- OMP's `stop-verify` now returns `decision:"block"` from `session_stop` (the Claude Stop-hook equivalent). `OMP_STOP_VERIFY_MAX` (default 5) is enforced by the extension because host `#emitSessionStopEvent` skips `SESSION_STOP_CONTINUATION_CAP` for block decisions.
- Claude's `swarm-stop-verify.sh` stays project-level (`.claude/settings.json`) by design; do not wire it into global settings.

## Tried and ruled out

- Wiring `swarm-stop-verify.sh` into the global Claude Stop hook: would block every response in unrelated repos for any dirty session-edited file; the project-only scope is intentional.
- Making Agy's `post-edit-lint.sh` return diagnostics: Antigravity's PostToolUse output contract is not documented in this repo, so returning a guessed `decision` could break the hook. Only the matcher bug (`edit_file` was missing) was fixed.
- Implementing LCM / RRSI / billion-context compression in this mission: each needs a new persistent store or external proxy and overlaps existing compaction/artifact mechanisms; documented as follow-ups in `agent/context/pi-techniques-30.md`.

## Watch out

- `bun test` in directory mode still fails with unresolved host packages (`typebox`, `@oh-my-pi/pi-ai`); the real gate is `agent/scripts/test-omp-extensions.sh` per-file mode.
- `session_stop` fires per settle (every assistant turn), not only at session end. The blocker intentionally mirrors Claude's Stop hook, but it also means transient lint errors mid-work force a continuation until the 5-attempt cap.
- `agent/scripts/sync-verify.sh` fails from a linked worktree because `$HOME` symlinks point at the main checkout; run it in the main checkout after merge.
