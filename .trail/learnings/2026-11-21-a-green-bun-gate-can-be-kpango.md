---
title: "A green bun gate can be a no-op, and a refresh script can match nothing and still exit 0"
author: Kpango
date: 2026-11-21
branch: main
id: l-b7e44f7f
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/claude/settings.json
  - agent/scripts/test-omp-extensions.sh
  - agent/skills/_swarm-common/refresh-index.sh
  - agent/skills/trail/SKILL.md
---

## Decided

- `agent/scripts/test-omp-extensions.sh` now treats `Ran 0 tests` from `bun test <file>` as "not run" and re-runs the file with `bun run`, counts `<N> pass` / `pass=<N>` as well as `<N> passed`, and fails when the total is 0. Suite went 1943 -> 2438 assertions.
- `agent/skills/_swarm-common/refresh-index.sh` matches the aligned `| §N | ... | a-b |` rows with variable-width padding and exits 1 when it rewrote no row.

## Tried and ruled out

- Blaming the cli-bridge failure on parallel-load flake: `bun test lib/cli-bridge.test.ts` runs 0 tests by design (async `main()` is not awaited), while directory-mode `bun test` does execute it and fails. Both modes are wrong for this file.
- Switching the whole gate to `bun run`: files that import `bun:test` exit 1 under it (sol-pi.test.ts, context-economy-pressure.test.ts). The fallback has to be per file.
- Detecting the test style by grepping for `bun:test`: the string appears in comments in cli-bridge/subagent-mesh, so grep misclassifies them. The runtime signal (`Ran 0 tests`) is the reliable one.

## Watch out

- A passing `validate-harness` line "omp extension unit tests (bun test)" can lie unless the script proves it executed assertions; keep the zero-count guard.
- `trail init`/upstream upgrades rewrite `agent/skills/trail/SKILL.md` to a 900+ char description (fails `test-catalog-health.sh`) and rename hook helpers to `graft-hooks.cjs`. Restore the SKILL.md frontmatter (`git checkout -- agent/skills/trail/SKILL.md`); the settings.json rename is the correct direction because only graft-hooks.cjs exists in ~/.claude/helpers.
- `test-common.sh` validates CORE.md only; it never invokes refresh-index.sh, so a broken refresh script stays invisible until SWARM.md moves.
