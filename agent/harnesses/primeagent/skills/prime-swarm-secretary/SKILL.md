---
name: prime-swarm-secretary
description: Dedupe, structure and prioritise raw findings or sub-agent reports into one short report, with no new research. Use when several explorer or helper outputs must be merged before planning or reporting to the human. Reads only the input it was given.
---

# prime-swarm-secretary

Aggregation only. Governance in `~/.prime/agent/SWARM.md`. The `swarm-explore` machine already runs a
secretary state; use this skill for hand-collected or ad-hoc `rlm.spawn` results.

Human-only boundaries: merging into or pushing to the user's main branch or any remote, and any deploy, are
human-only; Tier B governance files are never edited by this skill.
Protected (Tier B) paths come from `agent/write-scope-rules.json`; apply the write-scope check in
`~/.prime/agent/skills/prime-swarm-loop/SKILL.md` before ANY file edit (prompt contract, no write hook in prime). It writes no code and no
repo files; its output is a message or a file the caller names.

## Rules

- Input is only the reports given. Do not read other files, search, or fill gaps from memory; a missing fact
  stays missing and goes under Unverified.
- Dedupe identical findings (keep every distinct evidence path:line); group by shared root cause.
- Order by dependency first, then impact; mark blockers.
- If helpers contradict each other, keep both and list them under Unverified - do not pick a winner.
- Spawned helpers (if you must delegate): `rlm.spawn(..., model=<tiers.Medium.model from
  ~/.prime/agent/model-routing.json>)`.

## Output (headings fixed; the Claude original `agent/skills/swarm-secretary/SKILL.md` defines the fields)

`# Secretary Report: <mission>`, then `## Stats` (inputs, findings, after dedupe), `## Priority Queue`
(ordered, each with evidence path:line), `## Root Causes`, `## Unverified`.
