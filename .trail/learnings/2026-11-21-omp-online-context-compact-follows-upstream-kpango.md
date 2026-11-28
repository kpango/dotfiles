# OMP Online Context Compact follows upstream select-at-boundary / compact-at-settle

## Decided

- Two phases, like upstream: `update_plan` arms a boundary, `turn_end` prices it and calls
  `ctx.abort()`; the compaction runs at settle (`agent_end` with `willContinue=false`, `session_stop`
  as fallback) when `ctx.isIdle()`.
- Plan steps carry a stable id; only a previously-registered unfinished step becoming completed is a
  boundary (a fresh completed step is history). `progress` evidence waits in `pendingProgress` and is
  folded into the next compaction's instructions.
- The compaction passes `suppressContinuation: true`; the extension then sends its own resume
  reminder with `triggerTurn: true` (success → plan reminder, recoverable no-op → skipped reminder,
  other failure → resume once, then rethrow).
- Provider requests are counted in `before_provider_request` (flag set in `context`), not `turn_end`.

## Tried and ruled out

- Compacting inside `turn_end`: the summary lands in a live turn and OMP keeps running past the
  boundary.
- Reading a `reason` from `session_before_compact`: OMP's event has no reason field, so the guard
  exempts any compaction carrying `customInstructions` and cancels only on a selected boundary.
  Cancelling an _unselected_ native compaction below `window - reserveTokens` was tried and removed:
  it cannot fire for OMP's own threshold trigger (that fires near the window) and only ends up
  blocking the operator's plain `/compact`, which upstream never suppresses.
- Porting upstream `projection.ts` (`findCutPoint` + `buildSessionProjection`) verbatim: the helpers
  live behind the legacy shim, which pulls `pi-natives` and fails to load under `bun test`. Archive
  pricing stays the tail-sum `archiveTokensFor` estimate; if it ever needs to be exact, port it with
  a lazy runtime import and a test stub.

## Watch out

- A committed `session_compact` must clear `compactionRefused` and `observedMessages`; the next
  request re-projects via the `context` event, so a boundary priced before that sees zero archive and
  the `native_not_compactable` guard refuses it (correct, but surprising in tests).
- `input` events come from interactive and rpc only; `source === "extension"` never occurs today but
  is the only source treated as a non-task change.
- `OnlineState.outputTokens` is OMP-only (status mean output). Dropping it while porting the state
  shape silently yields `NaN` — bun tests do not typecheck; parse with `?? 0`.
- `ManualCompactionNoOpError` ("Already compacted", "Nothing to compact (session too small)",
  "Conversation is changing; cannot compact") is recoverable, but retry only after new user input or
  a real (non-`update_plan`) successful tool result.
