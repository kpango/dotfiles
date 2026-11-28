# AHE change manifest closes the failure-attribution gap in Harness² traces

## Decided

- The 30-technique PDF audit is pinned as `agent/context/pi30-applicability.md` using the **PDF's own
  numbering** (1–30). The pre-existing `pi-techniques-30.md` is a different list; only its #16 row now
  points at this audit.
- Adopted exactly one missing mechanism: the AHE change manifest (arXiv:2604.25850). Harness² traces
  now carry `manifest?: string[]` — the repo-relative files edited through tracked Action Fusion
  edit/write calls before the failure (≤20 per tool result, ≤512 unique per session) — so a clustered
  root cause can be attributed to a change set instead of one `target`. Shell-side edits are not
  observed.
- The manifest is **paths only** (no diff text, no hashes): the candidate already carries `new_text`,
  and the evolver only needs co-change attribution. Producer (`sol-pi.ts`) stores `editedFiles` as
  absolute paths when the edit is observed, then `sanitizeTraceManifest(root, ...)` makes them
  repo-relative, allowlist-valid, deduplicated, sorted, and capped at 32 entries × 300 chars
  (one slot is reserved for the failing `target`).
- Consumer (`harness2-offline.py`) validates the same invariants fail-closed (`parse_manifest`),
  reports `clusters[].manifests` as a union, and appends `manifest: a,b,+N` to the EXPERIENCE evidence.
- `appendEvolutionTrace` normalizes again and omits an empty manifest, so direct callers cannot write
  a malformed or unbounded record. It checks the serialized record size and appends only when
  `size + record <= traceMaxBytes`; the shipped cap is 960 KiB, below the consumer's 1 MiB read cap.

## Tried and ruled out

- Storing the full diff or per-file hashes in the trace: duplicates `new_text`, grows the per-repo
  JSONL, and adds no signal to clustering. Paths are enough for attribution.
- Making a bad manifest block the tool result: tracing is advisory; a malformed manifest is dropped
  at the producer and fails closed only when the offline pipeline is explicitly fed one.
- Porting AHE's Agent Debugger / trajectory selection / staged gates: model-dependent or already
  covered by Harness²'s candidate evaluation; the manifest was the only deterministic missing link.
- Adopting #12/#17/#22 embeddings/FTS5, #19 RRSI, #26 external compression proxy, #30 subprocess
  elimination: each adds a standing cost or removes an isolation boundary; the existing
  trail/codegraph/ast-grep/repl_filter and sandbox stack already cover the need.
- #4 Codemode, #10 LCM DAG, #25 autoresearch: host-owned or require a low-variance benchmark target;
  deferred rather than half-ported.

## Watch out

- `editedFiles` stores absolute paths at observation time; do not go back to storing raw tool-input
  paths, which may be relative to the session cwd (often a mission worktree subdirectory) and would be
  re-resolved against a different cwd later.
- `session_switch` / `session_clear` must reset `editedFiles`, `traceKeys`, the trace counters and
  `lastTraceFile` exactly like `session_start`, or a new session inherits the previous file set and
  silently suppresses traces.
- Trace text must go through `sanitizeTraceText`, which uses the parity-tested `hasUnsafeHarnessChar`
  (controls, Cf, variation selectors, Co/Cn/Cs). Missing even U+FE0F makes the whole per-repo JSONL
  unreadable for the consumer.
- `harness2-offline.py`'s cluster is rejected as `unclassified_target` unless the target classifies;
  manifest tests must use real component paths (`agent/scripts/x.py`, `agent/rules/r.md`,
  `agent/skills/foo/SKILL.md`), not synthetic `agent/a.go`.
- The manifest consumer is strict: non-array, non-string, absolute, `..`, >300 chars, or >32 entries
  are input errors (rc 2), not silently skipped.
- Do not enable OCC by default while touching traces: the OCC live path needs
  `keepRecentTokens >= 20000` and is intentionally a kill switch in `sol-pi.json`.
