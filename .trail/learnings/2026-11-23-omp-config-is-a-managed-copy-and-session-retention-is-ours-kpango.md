---
title: "OMP config.yml ships as a managed copy (not a symlink), and session retention is enforced by our extension"
author: Kpango
date: 2026-11-23
branch: main
cost: { minutes: 30, tokens: 0 }
id: l-1955efa6
scope: repo
status: active
src: agent
touches:
  - Makefile.d/install.mk
  - agent/sync-manifest.json
  - agent/harnesses/omp/extensions/session-search.ts
  - agent/harnesses/omp/extensions/lib/session-retention.ts
---

## Decided

`~/.omp/agent/config.yml` is now a **regular file (perm 600), not a symlink**, seeded by
`make omp/install`. OMP normalizes the config it loaded on every launch (strips comments,
overwrites `modelRoles.default` with the running model, appends `setupVersion`), so a symlink
pushed that runtime state into `agent/harnesses/omp/config.yml` and left the repo dirty after
every start. The install recipe re-copies canonical and re-applies the previously deployed
`modelRoles.default`, so the last-used model survives a reinstall without being committed.
`agent/sync-manifest.json` verifies the target as `live-regular-file` with perm 600.

Automatic session retention lives in `session-search.ts`: on `session_start` it prunes
transcripts older than `OMP_SESSION_RETENTION_DAYS` (default 30, `0`/`off` disables) and notifies
only when it deleted something. `/doctor` reports total transcript size, the three largest
transcripts, and whether config.yml is still a symlink.

## Tried and ruled out

Keeping the symlink and restoring with `update-model-catalog.py --sync-only` (the earlier
workaround): it works, but every session start re-dirties the file, so it cannot be the steady
state. Always-copy-on-install without preserving `modelRoles.default` was also rejected: the
deployed file would silently revert to the catalog default model on every `make omp/install`.

Patching the vendored `cli.js` for the `ud` / `session.rewrite` blocking path: the bundle
(`dist/cli.js`, ~1.5-1.7 s on a 400 MB transcript) is replaced on every OMP upgrade, so the only
lever is keeping transcripts small — that is what the retention policy above does.

## Watch out

- `make omp/install` intentionally overwrites a drifted deployed config; only `modelRoles.default`
  is carried over. Do not add other keys to the carry-over list without a reason.
- First conversion must copy the **deployed** content before restoring the repo file, otherwise the
  restart silently switches `modelRoles.default` to the canonical (anthropic) default.
- `OMP_SESSION_RETENTION_DAYS` deletion is global across projects and irreversible; `/sessions prune`
  remains the dry-run/manual path.
