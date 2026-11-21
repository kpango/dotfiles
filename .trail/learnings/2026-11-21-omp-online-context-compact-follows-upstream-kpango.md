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
  exempts any compaction carrying `customInstructions` and cancels only on a selected boundary or a
  window under `reserveTokens`.

## Watch out
- `OnlineState.outputTokens` is OMP-only (status mean output). Dropping it while porting the state
  shape silently yields `NaN` — bun tests do not typecheck; parse with `?? 0`.
- `ManualCompactionNoOpError` ("Already compacted", "Nothing to compact (session too small)",
  "Conversation is changing; cannot compact") is recoverable, but retry only after new user input or
  a real (non-`update_plan`) successful tool result.
