---
title: "SoL-Pi port fidelity: what is upstream-exact and what is an OMP adaptation"
author: Kpango
date: 2026-11-20
branch: main
id: l-4a4a1f50
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/claude/settings.json
  - agent/skills/trail/SKILL.md
  - agent/harnesses/omp/config.yml
---

## Decided

Audited the OMP SoL-Pi port against a fresh NVlabs/SoL-Pi clone (2026-11-21). Upstream-exact
semantics: ObservationPack thresholds/fullReplayTurns=2/id shape/masked archive/receipts never
repacked; EPR verbatim-quote verification with fail-closed fallback, quote<=4096B, receipt<=raw;
plan statuses and the state entry name. Verified-adapted (cannot be upstream-exact on OMP):

- Action Fusion calls `then_run` through /bin/sh after OMP's built-in edit/write; upstream holds
  mutation+command in ONE per-file queue slot. OMP's mutation runs before the extension sees the
  result, so only the command takes the queue. Consequence: an edit between mutation and queue
  acquisition is invisible to the hash guard; the guard only closes the yield window.
- Online Context Compact is a request-budget heuristic, NOT upstream's economics model (cost per
  request + cache-debt repayment + horizon + cooldown + window protection, and the
  abort-at-turn_end -> compact-at-agent_settled -> resume choreography). OMP has no agent_settled.
- EPR receipt contract differs: ours is prose + quote_sha256/authority/readback; upstream's is a
  single machine-readable JSON `{schema, source_sha256, status, uncertain, evidence[{kind,quote}]}`
  plus a key=value receipt. Ours also reduces bash results only, not fused edit/write then_run output,
  and reads the inline text instead of upstream's untruncated full-output file.
- Config: ours accepts a superset (nested sections, legacy flat kill switches, ignored unknown
  keys); upstream rejects unknown keys and is flat-only, so sol-pi.json is not upstream-loadable.
  Fixed now (aligning to upstream): placeholder carries a 1 KiB head/tail excerpt read with positioned
  reads; isError results are never packed; failed/skipped then_run marks the fused result isError.

## Tried and ruled out

- Re-deriving the placeholder excerpt by re-masking the raw projection text per request: masking a
  multi-MB log on every provider request is too expensive, and slicing before masking can leave a
  secret head. Reading the already-masked archive with positioned reads costs two reads of <=8 KiB.
- Making obs_recall byte-offset based like upstream: line-based paging is friendlier and already
  covered by tests; kept as a known deviation.

## Watch out

- Do not claim in comments/docs that the mutation runs inside the then_run queue: it does not.
- sol-pi.json's `onlineContextCompact: false` (top-level) overrides `onlineContextCompactConfig.enabled:
true` via the FLAG_MAP kill-switch; reading only the nested block makes OCC look enabled.
- agent/harnesses/omp/config.yml is a symlink into the repo and OMP rewrites it at runtime
  (modelRoles.default, setupVersion, comment stripping) -> `update-model-catalog.py --check` reports
  drift; restore with the generator, never hand-edit.
