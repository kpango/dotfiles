# CONTEXT.md — domain terms and invariants

Persisted per the Grilling design-interview protocol (`agent/rules/grill-interview.md`) at the end
of the jev-swarm-integration mission (2026-09-19). Captures terms/invariants this mission's design
decisions (see `docs/adr/ADR-0003-jev-swarm-decision-integration.md`) depend on, for whoever
resumes the deferred implementation.

## Terms

- **Jev**: TypeSafeAI's typed decision model/API (`https://typesafe.ai`). NOT an LLM — does not
  generate text; takes a `state` (context) plus typed `questions` (`Choice`/`Score`/`Noul`) and
  returns structured answers with a `confidence` scalar and a per-option `probabilities` map.
  Hosted API only, early-access/waitlist-gated as of 2026-09-19 (no self-hostable/OSS model
  weights), $0.042/Mtok input + free output, 70-500ms claimed latency, no built-in local fallback
  in the official SDK.
- **The 2 candidate decision points** (ADR-0003's entire scope — see that ADR's inventory table
  for the other 9 decision points and why each is out of scope):
  - **Fixer's GraSP classification**: `agent/skills/swarm-implement/SKILL.md`'s Fixer
    (`debugger` subagent) categorizes its root-cause diagnosis into one of 5 repair primitives
    (Rebind/InsertPrereq/Substitute/Rewire/Bypass) as free prose, parsed by regex today.
  - **CHECKPOINT's MAST routing**: `agent/skills/swarm-loop/SKILL.md` Phase 4's routing of a
    failed task into one of 3 MAST categories (system design issue / inter-agent misalignment /
    task verification failure), also prose-derived today.
- **"Authoritative when available, fallback-only otherwise"** (ADR-0003 decisions 3+4): the
  pattern this design uses for Jev — never a hard dependency, always a best-effort upgrade over
  the pre-existing prose+regex mechanism.

## Invariants this mission's decisions depend on

- **No code ships from this mission.** `docs/adr/ADR-0003-jev-swarm-decision-integration.md` and
  this file are the entire deliverable. Do not treat their existence as evidence that Jev is
  wired into this repo anywhere — it is not, as of this mission.
- **The scope is fixed at exactly 2 decision points**, not "wherever seems useful" — re-opening
  the other 9 (6 deterministic + 3 already-schema-forced) needs a new ADR with a different
  argument, not an extension of ADR-0003, since the reasons they're excluded (already free/fast,
  or already type-safe from the same LLM call) don't change with API-key availability.
- **Jev must never become a hard gate on swarm-loop's autonomous progress.** Any implementation
  of ADR-0003 that makes a missing key, a timeout, or a low-confidence answer block/stall the
  loop (rather than falling through to the existing prose-parse path) violates decision 3's
  design intent, regardless of how that fallback is implemented in code.
- **Before resuming implementation, re-verify DeepResearch facts in ADR-0003 are still current** —
  typesafe.ai was a 4-day-old early-access product at the time of this research (2026-09-19);
  pricing, SDK shape, and the waitlist-gated access model are all plausible candidates for change
  before an API key is actually obtained.
