# ADR-0003: Jev typed-decision integration — design only, implementation deferred

## Status
Accepted-design, implementation deferred (human-approved via Grilling design interview,
2026-09-19, jev-swarm-integration mission). No code changes ship with this ADR — see
"Consequences" for why, and "Resuming this work" for how to pick it up later.

## Context

The user asked whether TypeSafeAI's Jev (a typed decision API, distinct from an LLM — see
`docs/adr/ADR-0002-graft-graphify-consolidation.md`'s prior research summary for the product
overview) could accelerate decision-making effectiveness, type safety, and directional-confidence
safety in this repo's Swarm-family workflows (`swarm-loop`/`swarm-implement`/`swarm-explore`/
`swarm-graph`/`swarm-meta`).

### DeepResearch findings (this mission)

**Access precondition** (confirmed via typesafe.ai, docs.typesafe.ai, console.typesafe.ai):
Jev is early-access/waitlist-gated — there is no instant self-serve signup. No documented typical
wait time. **This repo's environment does not currently have a Jev API key.**

**SDK/API shape** (confirmed via docs.typesafe.ai/introduction/quickstart.md,
typesafe-sdk-js's `types.ts`): `client.system_one(state=..., questions={...})` takes a `state`
context plus one or more typed questions (`Choice`/`Score`/`Noul`) in a single call ("fan-out",
recommended — "adding questions barely changes the response time"). The response carries both a
scalar `confidence` and a full per-option `probabilities` map.

**Reliability** (confirmed via docs.typesafe.ai/api.md, sdk/python/api/retries.md): 70-500ms
end-to-end latency claimed. SDK default retry: up to 2 retries, exponential backoff capped at
5s, **30s total retry budget**. **No built-in local fallback** — a separate,
manually-swapped package (`system-one-adapter-python`) exists for LLM-backed substitution, but
the official SDK itself is hard-required-online.

**Reference integration** (`prismhq/jev-router`, confirmed via its README + source): calls Jev
once per LLM request in the hot path (5s timeout), with a local `RulesDecider` (cheapest-eligible
heuristic, no API) as the no-key fallback.

### Internal inventory (this mission's Explore agent, read-only survey of
`agent/skills/{swarm-loop,swarm-implement,swarm-explore,swarm-meta}/SKILL.md` +
`agent/skills/swarm-implement/scripts/*.sh` + `agent/hooks/claude/swarm-fable-gate.sh`)

11 discrete decision points found across the Swarm family:

| Category | Count | Examples | Jev fit |
|---|---|---|---|
| (a) Deterministic (code/regex/static rule) | 6 | `harness-select.sh` harness pick, `swarm-loop` Phase -1 SCALE, complexity gate, `budget-guard.sh`, `swarm-fable-gate.sh`, `swarm-graph` GRAPH-FIT | **None** — already zero-cost, zero-latency, no LLM involved; Jev would only add cost/latency/external dependency for no type-safety gain |
| (b) Already schema-forced LLM | 3 | `swarm-implement` Checker PASS/FAIL+MAST (`Workflow` `schema` param), `swarm-explore` finding severity enum, `swarm-explore` `low_quality_shards` judgment | **None** — these already get type safety from Claude's own schema-forced structured output, in the same call that also generates the needed prose; Jev cannot generate that prose (it is a non-generative typed-decision model), so it could only ever *add* a redundant second call here, not replace anything |
| (c) Unforced prose LLM (caller must parse) | 2 | `swarm-implement` Fixer's GraSP repair-primitive classification (Rebind/InsertPrereq/Substitute/Rewire/Bypass); `swarm-loop` Phase 4 CHECKPOINT's MAST routing | **Real candidates** — the only two decision points in the entire inventory with genuine headroom, since they currently rely on prose + regex-parsing rather than an enforced schema |

## Decisions (Grilling design interview, 2026-09-19)

1. **This mission delivers design only.** ADR + this scope note are the entire deliverable;
   no code is written or wired in this pass. Rationale (human-selected): no Jev API key exists
   in this environment yet (waitlist not cleared), the benefit is narrow (2 of 11 decision
   points), and Jev can only *add* a call rather than replace an existing one (see inventory
   table) — writing untested integration code against an API this environment cannot currently
   call would be premature. Re-evaluate/implement once API access is obtained (see "Resuming
   this work" below).
2. **Scope: both of the 2 unforced-prose candidates, via one shared adapter.** Fixer's GraSP
   classification (`swarm-implement`) and CHECKPOINT's MAST routing (`swarm-loop`) are covered
   by a single design so a future implementer builds one reusable abstraction rather than two
   bespoke integrations. Explicitly **not in scope**: the 3 already-schema-forced decision points
   (no benefit, see table) and the 6 deterministic ones (no benefit, adds a dependency for
   nothing).
3. **Fallback: Jev calls are always optional, silent no-op on failure.** Missing API key,
   exception, or timeout falls through to the existing prose+regex-parse path unconditionally —
   the swarm loop's autonomous progress is never blocked on Jev's availability. Same principle as
   ADR-0002's session-start hook removal: an external dependency must be pull-based and
   fail-silent, never a hard gate on the main execution path.
4. **Authority: Jev is authoritative when it succeeds; prose-parse is fallback-only.** When Jev
   returns a result above the confidence threshold (decision 6), its `Choice()` answer *replaces*
   the regex-parsed prose classification as the actual routing decision — this is a deliberate,
   more consequential choice than a mere consistency-check design, made because it also retires
   the existing classification's fragility (today: "prose with embedded classification, no schema
   validation, parser regex required" per the inventory). The underlying prose itself (the
   Fixer's actual fix plan, CHECKPOINT's diagnostic narrative) is untouched — only the categorical
   routing label's source changes.
5. **`state` input: raw error/diff/context, NOT the Fixer's/CHECKPOINT's own self-reported
   analysis.** Jev is deliberately kept blind to the existing prose classification's own
   conclusion, so it functions as a genuinely independent second opinion rather than an
   extraction pass over text that has already anchored on an answer. Trade-off accepted: larger
   `state` payload than "classify this existing text" would need (still cheap at $0.042/Mtok),
   and any place where Fixer/CHECKPOINT's self-analysis and Jev's independent read disagree needs
   no separate handling — decision 4 already resolves it by construction (Jev wins outright
   above threshold, prose wins outright below it; there is no third "disagreement" state to
   design for).
6. **Low-confidence handling: below-threshold Jev answers degrade to the fallback path**, treated
   identically to a missing key or API error (decision 3's fallback, not a human escalation).
   Default threshold: 0.5 (tunable at implementation time — no production data exists yet to tune
   against). Rationale: keeps the failure mode uniform (one fallback path, not two), and errs
   toward not blocking autonomous progress, consistent with decision 3.

## Consequences

- **No functional change ships from this mission.** The 2 candidate decision points continue
  using their current prose+regex-parse mechanism unchanged until a follow-up mission implements
  this design against a real API key.
- **This design intentionally narrows Jev's footprint to 2 of 11 decision points.** The other 9
  are explicitly and permanently out of scope under this ADR (not merely deferred) — re-opening
  them would need a new ADR with a different cost/benefit argument, since "already free/fast" (6
  points) and "already type-safe from the same call" (3 points) are not circumstances a future
  API-key acquisition changes.
- **Externalizes a new hard dependency** on a single-vendor, non-OSS, early-access hosted API for
  2 low-frequency (Circuit-Breaker-triggered) decision points — decisions 3 and 6 exist
  specifically to keep this from ever becoming a reliability regression, at the cost of Jev's
  value being fully opportunistic (best-effort upgrade, never guaranteed).
- **Cost/latency framing differs from ADR-0002.** ADR-0002 removed graft hooks because they fired
  on every turn/edit (high frequency × latency = real cost). This ADR's 2 candidates fire only on
  Circuit-Breaker triggers (Fixer invocation) or CHECKPOINT failure routing — low frequency — so
  the 70-500ms + retry-budget cost per call is not expected to be user-visible in aggregate, even
  though it is real per-call.

## Resuming this work

When a Jev API key becomes available:
1. Re-open (or re-invoke `/swarm-loop` directly for) this mission's scope with `swarm-implement`
   at `standard` or `complex` complexity (multi-file: a new shared adapter + two call sites in
   Tier-B `SKILL.md` files).
2. The shared adapter's exact shape (script language, where it lives, how the API key is sourced
   — likely `pass show ai/<something>` per this repo's existing secret-management convention) is
   deliberately left undecided here — a Level-4 Implementation&Tests question, out of scope for a
   design-only mission with no key to test against.
3. Both call sites (`agent/skills/swarm-implement/SKILL.md`'s Fixer step,
   `agent/skills/swarm-loop/SKILL.md`'s Phase 4 CHECKPOINT) are Tier-B protected — implementation
   needs `budget-guard.sh --write-scope-grant` per edit, same as this session's ADR-0002 work.
4. Re-verify the DeepResearch facts in this ADR are still current (typesafe.ai is a 4-day-old
   early-access product as of this writing, 2026-09-19 — pricing/SDK/access model may change).
