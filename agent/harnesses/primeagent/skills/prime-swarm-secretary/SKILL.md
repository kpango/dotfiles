---
name: prime-swarm-secretary
description: Dedupe, structure and prioritise raw findings or sub-agent reports into one short report, with no new research. Use when several explorer or helper outputs must be merged before planning or reporting to the human. Reads only the input it was given.
---

# prime-swarm-secretary

Aggregation only. Governance in `~/.prime/agent/SWARM.md`. The `swarm-explore` machine already runs a
secretary state; use this skill for hand-collected or ad-hoc `rlm.spawn` results.

## Human-only boundaries

Only the human merges into or pushes to the user's main branch or any remote, deploys, removes a worktree,
deletes a branch, approves a Tier B change and approves the GATE; no prime-swarm-* skill and no machine it starts
does any of these. Tier B = what `swarm_adapter.tier_b_hits(<worktree>, [<repo-relative path>], expect_common_dir=<common_dir>)`
reports from the dotfiles `agent/write-scope-rules.json` next to the adapter, never the target repo's copy:
before any file edit pass the path to it and do not edit on a hit, an `error` or `exit_code` != 0. Commits and
merges happen only through the "Commit and merge (caller side)" blocks of `swarm-adapter/SKILL.md`, on
`swarm-prime/*` branches. The skill text itself runs no git command in the target repository, read-only ones
included (its config and hooks are maker-writable), and reads it only through `swarm_adapter`. Residual risk: the
adapter's seven primitives `change_set`, `tier_b_hits`, `stage_task`, `incoming`, `verify_merge`, `commit_tree` and
`update_ref` are all that its "no git command runs in the target repository" guarantee covers. Steps outside them,
`swarm_adapter.worktree_alloc`, `swarm_adapter.mission_init`, `harness-select.sh`, the `swarm-implement` init
(`rev-parse HEAD`, MACHINE.md) and Checker (`diff <init.base>`, `ls-files`), `swarm-review` (`merge-base`, `diff`,
`ls-files`) and `swarm-explore` (`log`, `show`), run git commands in the target repository, so its config and hooks
can run there; the repo's own gate commands (release gate step 2) are maker-writable too. Maker-written config
(`diff.external`, `textconv`, ...) can shape the output of those git commands, and the Checker verdict and the review
summary rest on that output. A STOP hands the decision to the human; never resume on silence. Governance:
`~/.prime/agent/SWARM.md`.

It writes no code and no repo files; its output is a message or a file the caller names.

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
