# SoL-Pi bridges OMP to the swarm mission, Harness² traces and Trail

## Decided

- Mission state is injected as **text into the request system prompt** (`before_agent_start`), not as a
  tool: OMP's system prompt is the only surface that is present on every request and survives a
  compaction without an extra model turn. The snapshot is bounded (~600 chars) and only changes when
  `@fix_plan.md` changes.
- `@fix_plan.md` is found by walking up to 4 levels from the session cwd (a mission runs inside its
  worktree, often in a subdirectory) and cached by `(mtimeMs, size)`; the file stays the single source
  of truth, the snapshot is derived and never persisted.
- The same snapshot is added to the boundary-compaction `internalGuidance` and to the post-compaction
  resume reminder, so a long mission does not lose its task list to summarization (ConstraintRot).
- Harness² traces reuse the existing deterministic observations: an Action Fusion validator failure
  and a failed fused `then_run`. They are written in the pipeline's JSONL shape
  `{signature, task, target, message}` and de-duplicated per `(signature, task, target)` until restart.
- `normalizeFailureSignature` replaces paths, digests and _all_ numbers (including an `exit-<n>` kind)
  with `<path>`/`<hash>`/`#` so the same root cause clusters across runs and exit codes still
  separate into their own clusters.
- Trail learnings are read on the compaction path only (`readdir` + newest 5 titles) and rendered as a
  one-line `trail ask` / `trail check` reminder, because OMP has no automatic SessionStart hook for
  Trail.

## Tried and ruled out

- Injecting the mission as a tool result or a `pi.sendMessage` turn: it costs a turn and the
  compacted history can drop it; the system prompt is the stable surface.
- Recording every tool failure as a trace: `harness2-offline.py` only classifies harness targets
  (`SYSTEM.md`, `AGENTS.md`, `rules/*.md`, `agents/*.md`, `skills/*/SKILL.md`, `scripts/**/*.py`,
  `extensions/**/*.ts`). Product-code failures are valid input but rejected as
  `unclassified_target`, so the recorder stays limited to Action Fusion observations and dedupes.
- Writing traces to the repo: the worktree is disposable and traces are evidence, not config; the
  default is `~/.claude/session-data/swarm/evolve-traces/<repo>-<digest>.jsonl` (shared by every
  session of the checkout), overridable via `omp.missionBridge.traceDir`.

## Watch out

- `row.ts`-style mission tables vary: the parser requires `task-id` and `status` headers but falls back
  to the first/last cell. A plan with no table rows reports `tasks.total = 0` and can never be
  `gateReady`.
- `harness2-offline.py` rejects a traces file as a whole on any control character; `sanitizeTraceText`
  must strip `\u0000-\u001f`, `\u007f`, `\u200b-\u200f`, `\u2028/\u2029` and BOM from signature/task/
  target, and collapse whitespace in `message`.
- Tests must set `missionBridgeConfig.traceDir` into the sandbox (`extCfg()` does), otherwise a
  validator-failure test appends records to the developer's real `~/.claude/session-data`.
- The OMP symlinked `config.yml` is still rewritten at runtime; the bridge reads `sol-pi.json` and
  nothing else, so no extra defensive handling is needed there.
