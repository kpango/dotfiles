---
name: prime-swarm-loop
description: Linear swarm mission for Prime Agent - scale check, mission init in an isolated worktree, explore, plan, implement each task with a Maker/Checker machine, adversarial review, then stop at a human gate. Use when the user asks for a multi-step code change, "swarm loop", or a mission on a repo where tasks run one after another. Never merges or pushes.
---

# prime-swarm-loop

Governance (tiers, budgets, human gates, Tier B rules) is defined in `~/.prime/agent/SWARM.md`; this file only
sequences the prime-native pieces. Run everything from the Python REPL. Load `swarm-adapter` for the API
(`swarm_adapter.*`); the three machines are `swarm-explore`, `swarm-implement`, `swarm-review` (each MACHINE.md
has its input JSON, run recipe and residual risks - read it before the first run).

## Human-only boundaries (never crossed by this skill)

- Merging into or pushing to the user's main branch or any remote, any deploy, branch deletion and worktree removal
  are human-only; the loop ends at GATE. Committing in the mission worktree, and merging a task worktree branch into
  the mission worktree (`prime-swarm-graph`), is orchestrator work and allowed.
- Tier B governance files are never edited (write-scope check below). If the task needs one, stop and tell the human.
- Mission work happens only in the worktree from `swarm_adapter.worktree_alloc`, never in the main checkout.

## Write-scope check (shared by all prime-swarm-* skills)

Tier B = the paths in `agent/write-scope-rules.json` (repo path; installed copy `~/.prime/agent/write-scope-rules.json`
if present). Before ANY file edit by you or in a task spec you write, resolve the target's absolute path and test it
against `suffix_patterns` and `fixed_absolute_path_patterns` (fnmatch; `${HOME}` -> home dir, see its `$comment`).
On a match: do not edit, refuse, and escalate to the human.

    import json, os, fnmatch; r = json.load(open("<rules path>")); h = os.path.expanduser("~"); p = os.path.realpath("/abs/target")
    print(any(fnmatch.fnmatch(p, g) for g in r["suffix_patterns"]) or any(fnmatch.fnmatch(p, g.replace("${HOME}", h)) for g in r["fixed_absolute_path_patterns"]))  # True = protected

Residual risk: prime has no write hook, so this is a prompt contract, not an enforced gate. Include the list of
protected targets you checked in the GATE report.

## Success rule for every machine run

Use each machine's own **Success rule** (MACHINE.md) verbatim: `rlm.factory.status(run_id)` state `done` AND its
output file present (implement: `outcome.json` with `status: pass`). Anything else (paused, stopped, failed,
`done` without the file) is NOT success. Then: `await rlm.factory.status(run_id)`, `await rlm.factory.stop(run_id)`,
and follow the MACHINE.md instruction (fresh run directory, resize budgets, or escalate to the human). Branch on
status/exit codes, never on prose. Start runs of one machine one at a time (shared pointer file).

## States

1. **SCALE** - `interactive` (one small change, no worktree churn) or `mission` (several tasks, or any
   impact-C change per `agent/rules/impact-scope.md`). Unsure: `mission`.
2. **INIT** - `swarm_adapter.worktree_alloc(slug, scale, cwd=<repo>)` then
   `swarm_adapter.mission_init(slug, goal, scale, cwd=<worktree>)`; stop if either result has `error`/non-zero
   `exit_code`. All later steps use the returned worktree path; keep its `base` sha as the review `base_ref`.
3. **EXPLORE** - skip for a known, small target. Otherwise run `swarm-explore` with
   `{"question", "roots": [<worktree>]}`; the report is `<run_dir>/report.md`. Read the report, not raw shards.
4. **PLAN** - write `@fix_plan.md` in the worktree: tasks with id, spec, deps, and the verification commands
   (the repo's own build/test/lint). If the design is ambiguous or touches a shared contract, grill the human
   first (grill-interview rules (read `~/.prime/agent/skills/grill-interview/SKILL.md` if present, else ask the human directly): one question at a time, 2-4 options with a `[Recommended]` badge) and
   record decisions in `CONTEXT.md` before any edit. For an architectural dead end use `prime-swarm-architect`.
5. **EXECUTE** - for each task in dependency order, run `swarm-implement` with
   `{"mission", "task_spec", "worktree", "commands", "test_commands"}`. Size `budget_ms` first if the gate takes
   long (MACHINE.md Residual risks). One task = one run directory.
   - Budget: the machine already calls `swarm_adapter.budget_guard` (5 attempts per run, 20 per mission). If the
     mission budget is exhausted or `outcome.json` is `escalated`, stop and report; do not raise limits.
   - After `pass`, `git diff` in the worktree is the evidence to show, not the checker prose. Then commit it (the
     maker does not commit): stage every changed and untracked path by name (from `git status --porcelain`) and
     `git commit -m "<task-id>: <summary>"`, via `swarm_adapter.decide_shell`, so the next task's checker diff
     (`git diff <init.base>`) holds only that task's change.
6. **REVIEW** - run `swarm-review` with `{"worktree", "base_ref": <INIT base sha>}` once all tasks pass. Run success (Success rule)
   and verdict are separate: read `summary.all_pass` and `summary.failed`. Failed lenses become new tasks (back to
   EXECUTE, max 2 review rounds), then stop and report.
7. **GATE** - present: task outcomes, `git diff --stat`, review summary, residual risks. Then
   read `~/.prime/agent/skills/prime-swarm-release-gate/SKILL.md` and follow it (or ask the human to run `/skill:prime-swarm-release-gate`). STOP and wait for the human.

## Optional tools (only where they add value)

- `goal.create(...)` only if the human explicitly asked for a persistent goal; never infer one.
- `rlm.spawn(prompt, name=..., model=<selector>)` for ad-hoc read-only helpers. `model` is the exact
  `tiers.<Tier>.model` value from `~/.prime/agent/model-routing.json`: `tiers.Low` for bulk reading,
  `tiers.Medium` for summarising, `tiers.High` for edits (Maker), `tiers.XHigh` for independent checking,
  `tiers.Max` only for design (see `prime-swarm-architect`). Never hard-code a selector.
- Spot Max-tier help on a stuck task: `swarm_adapter.fable_grant(task_id, mission=<mission slug>)` first; allowed
  only when `exit_code` is 0; any other value (1, 2, 127, ...) or an `error` key means denied.
- Shell guard: for any command not run through a machine, `swarm_adapter.decide_shell(cmd, cwd)`; `block` or
  `ask` means do not run it and ask the human.
