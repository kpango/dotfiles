---
title: "OCC boundary compaction is only observable in a persistent session, and the host sets the real keep tail"
author: Kpango
date: 2026-11-21
branch: main
id: l-2a225e26
scope: repo
status: active
src: agent
---

## Decided
- The shipped Online Context Compact choreography (abort at `turn_end`, `ctx.compact()` from `agent_end`) is verified end-to-end in an OMP RPC session (`omp --mode rpc`): `prompt_result` status `aborted` + `sessionSettled:true` -> `manual_compaction_start` -> `manual_compaction_end` with a real `result.summary` (session file gets a `compaction` entry, `tokensBefore` ~19k) -> a second `agent_start` that answers from the reduced context. `bun test`, `test-omp-extensions.sh`, `validate-harness.sh` stay green.
- Live compaction checks must use a persistent session (RPC or TUI), not `omp -p`.

## Tried and ruled out
- Calling `ctx.compact()` directly from `turn_end` (host-tracked foreground compaction instead of the unawaited `agent_end` flush) was implemented and tested, then reverted: the host accepted the call path but the same no-op applies, and `-p` still ends the process as soon as the abort rejects the prompt, so nothing is gained over the committed design.
- `sol-pi.json` `omp.onlineContextCompact.outputReserveTokens`/`keepRecentTokens` only drive our *pricing*; they do not move the host's compaction cut point.

## Watch out
- `-p` (print mode): the boundary abort rejects `session.prompt()`, the CLI prints "Request was aborted" and exits, so a settle-time compaction is never observed there (EXIT=1). Do not read that as an extension failure.
- The host refuses to summarize when its own cut leaves nothing: `prepareCompaction` returns undefined and `compact()` throws `ManualCompactionNoOpError("Nothing to compact (session too small)")`. With `~/.omp/agent/config.yml` `compaction.keepRecentTokens: 20000`, a ~18k-token session is too small; force a real run with >20k of read output (6 x 28KB files worked) or temporarily lower the host keep tail.
- Window-protection selection (our side) can be forced for testing with a huge `outputReserveTokens` (e.g. 199000), but the host still needs enough history to summarize.
