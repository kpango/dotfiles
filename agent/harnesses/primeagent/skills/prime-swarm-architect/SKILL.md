---
name: prime-swarm-architect
description: Read-only architecture design proposal or spot diagnosis by the top (Max) model tier via rlm.spawn. Use when the human asks for a design proposal or architecture decision, or when a task is stuck after repeated failures and needs a root-cause diagnosis. Never edits files or runs state-changing commands.
---

# prime-swarm-architect

Output only; implementation goes to `prime-swarm-loop`/`prime-swarm-graph`. Governance in `~/.prime/agent/SWARM.md`.

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

This skill makes NO edits and runs no state-changing command at all, in the main checkout or in any worktree.

## Steps

1. **Spot diagnosis only** (stuck task, contradicting evidence): `swarm_adapter.fable_grant(task_id, mission=<mission slug>)`
   first (`task_id` gives the per-task cap, `mission` the per-mission cap; both apply). Allowed only when `exit_code`
   is 0; any other value (1, 2, 127, ...) or an `error` key means denied: do not spawn, stop and escalate to the
   human instead. Full design proposals are started by the human; do not self-start them.
2. Gather the raw evidence yourself (failing output, plan, relevant files with paths). Do not summarise it
   away: the child sees only what you put in the prompt.
3. Spawn one child, read-only by instruction:
   `await rlm.spawn(prompt, name="architect", model=<tiers.Max.model from ~/.prime/agent/model-routing.json>)`.
   Max is the top tier (currently `prime-inference/anthropic/claude-fable-5.1`); read the value from the file at
   run time. The prompt must say: read-only, no edits, no shell commands that change state, answer in the
   format below. Wait for the handle result.
4. Return the child's proposal to the human unedited apart from trimming. If it proposes edits to a Tier B file,
   mark that item "needs human"; never apply it.

## Output format

Headings, in order, as in the Claude originals (`agent/skills/swarm-architect/SKILL.md`, "提案書フォーマット" and
"診断書フォーマット"; follow those headings, they are not repeated here):

- Design mode: `# Proposal: <title>` with sections Background and problem, Constraints, Design options
  (recommended first, each with trade-offs and blast radius), Implementation plan (tasks sized for
  `swarm-implement`, dependencies, verification), and for a stuck task the root-cause analysis plus ordered
  hypotheses for the next attempts.
- Spot mode: `# Spot Diagnosis: <title>` with Trigger and raw evidence, Root cause (one paragraph), Recommended
  actions (ordered), Whether implementation intervention is needed, Whether human escalation is needed.
