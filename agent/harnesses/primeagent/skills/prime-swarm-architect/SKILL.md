---
name: prime-swarm-architect
description: Read-only architecture design proposal or spot diagnosis by the top (Max) model tier via rlm.spawn. Use when the human asks for a design proposal or architecture decision, or when a task is stuck after repeated failures and needs a root-cause diagnosis. Never edits files or runs state-changing commands.
---

# prime-swarm-architect

Output only; implementation goes to `prime-swarm-loop`/`prime-swarm-graph`. Governance in `~/.prime/agent/SWARM.md`.

Human-only boundaries: no merge, push or deploy without explicit human approval; Tier B governance files are never edited by this skill.
Protected (Tier B) paths come from `agent/write-scope-rules.json`; apply the write-scope check in
`~/.prime/agent/skills/prime-swarm-loop/SKILL.md` before ANY file edit (prompt contract, no write hook in prime). This skill makes NO edits and
runs no state-changing command at all, in the main checkout or in any worktree.

## Steps

1. **Spot diagnosis only** (stuck task, contradicting evidence): `swarm_adapter.fable_grant(task_id, mission=<mission slug>)` first (the per-mission cap needs `mission`);
   `exit_code` 1 = denied, then stop and escalate to the human instead. Full design proposals are started by the
   human; do not self-start them.
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
