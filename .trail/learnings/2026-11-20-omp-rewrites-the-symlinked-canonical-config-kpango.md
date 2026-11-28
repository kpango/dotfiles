---
title: "OMP rewrites the symlinked canonical config.yml at startup, so agent/harnesses/omp/config.yml drifts"
author: Kpango
date: 2026-11-20
branch: main
cost: { minutes: 4, tokens: 86483 }
id: l-52c503ed
scope: repo
status: active
src: agent
touches:
  - agent/scripts/update-model-catalog.py
---

## Decided

`~/.omp/agent/config.yml` is a symlink to `agent/harnesses/omp/config.yml`, and OMP rewrites that
file on startup: comments are stripped, `setupVersion: 3` is appended, `defaultThinkingLevel` and
`modelRoles.default` are overwritten with the running session's model. Treat the repo file as
canonical and restore it with `python3 agent/scripts/update-model-catalog.py --sync-only`, then
confirm with `--check` (which reports `FAIL: drift` while the rewrite is in place).

## Tried and ruled out

Treating the rewrite as a config bug: it is OMP normalizing the YAML it loaded, not a generator
defect. Committing the rewritten file instead of restoring it would bake a session model into
`modelRoles.default`, which is what the earlier "restore generator-rendered omp config.yml" fix had
to undo.

## Watch out

`settings.json` is kept out of the symlink set for the same reason (`migrateJsonToYml` would destroy
it). Any OMP session that happens to be running against the repo leaves `git status` dirty for
`config.yml`; always diff before committing and never include the runtime rewrite.
