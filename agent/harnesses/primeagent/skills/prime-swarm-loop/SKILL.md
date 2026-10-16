---
name: prime-swarm-loop
description: Linear swarm mission for Prime Agent - scale check, mission init in an isolated worktree, explore, plan, implement each task with a Maker/Checker machine, adversarial review, then stop at a human gate. Use when the user asks for a multi-step code change, "swarm loop", or a mission on a repo where tasks run one after another. Never merges or pushes.
---

# prime-swarm-loop

Governance (tiers, budgets, human gates, Tier B rules) is defined in `~/.prime/agent/SWARM.md`; this file only
sequences the prime-native pieces. Run everything from the Python REPL. Load `swarm-adapter` for the API
(`swarm_adapter.*`); the three machines are `swarm-explore`, `swarm-implement`, `swarm-review` (each MACHINE.md
has its input JSON, run recipe and residual risks - read it before the first run).

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

`<common_dir>` is always the `common_dir` that `worktree_alloc` returned (taken before any maker ran). Residual
risk: prime has no write hook, so the edit check is a prompt contract; put "never edit Tier B
(write-scope-rules.json) files" into every `task_spec`. The commit-time check below is the enforced one.

## Commit rule (shared by all prime-swarm-* skills)

Branch invariant: a task's work lives on the `swarm-prime/*` branch `worktree_alloc` created for it, and only the
adapter's `update_ref` (inside the "Commit and merge (caller side)" blocks) moves it. `<tip>` = the commit that
branch must be at: `worktree_alloc`'s `base`, then the `c["commit"]` each finished commit block wrote. Keep `<tip>`
in the REPL next to `<common_dir>` for every run of that worktree, retry runs included; never take it from a run's
`init.base`, the worktree or `@fix_plan.md` (a maker can move or write them). If `<tip>` or `<common_dir>` is
unknown (REPL or kernel restart, resumed session, ...): STOP and ask the human; never re-derive it from HEAD, the
commit history, a worktree or `@fix_plan.md`. To commit a finished task in worktree `<wt>`, call in this order, all with
`expect_common_dir=<common_dir>`:
`cs = await swarm_adapter.change_set(<wt>, <tip>, expect_common_dir=<common_dir>)` (fails unless
`cs["commits"] == 0`; 0 does not prove HEAD is `<tip>`: a HEAD reset to an ancestor of `<tip>` also gives 0, and
`stage_task` plus the `st["head"]` check below catch that),
`await swarm_adapter.tier_b_hits(<wt>, list(cs["paths"]), expect_common_dir=<common_dir>)`,
`st = await swarm_adapter.stage_task(<wt>, <tip>, expect_common_dir=<common_dir>)` (fails unless `st["head"]`
equals `<tip>`), then, unless `st["zero_diff"]`, the adapter's commit block with `st` and msg
`"<task-id>: <summary>"`, and set `<tip>` to its `c["commit"]`. Copy nothing of the blocks here; run them as
written in `swarm-adapter/SKILL.md`.

**HEAD check** (before REVIEW and before the GATE): `hv = await swarm_adapter.verify_merge(<wt>, <tip>,
expect_common_dir=<common_dir>)` must succeed (Success rule) and `hv["head"]` must equal `<tip>`, then
`hc = await swarm_adapter.change_set(<wt>, <tip>, expect_common_dir=<common_dir>)` must succeed with `hc["branch"]`
equal to the allocated `branch` (HEAD attached to it, so that branch is at `<tip>`; a detached HEAD gives `""`). A
commit after the last finished commit block (no Checker saw it), a HEAD reset below `<tip>`, or the branch moved
while HEAD was detached at `<tip>` fails it: STOP and report the raw result.

**Success rule** (one rule for every call above and for both adapter blocks): a step succeeds only when its result
has `exit_code` 0, no `error` key, an empty `hits`/`tier_b`, `cs["branch"]` equal to the allocated `branch`, every
condition the Commit rule attaches to it holds, and the block finished without raising. Anything else = nothing
further is committed or merged: the task is `blocked(spec)` when a Tier B path was reported, else
`blocked(design)` (a branch moved by anything but `update_ref` included); STOP and report the raw result to the
human. On success, `st["zero_diff"]` true means the task is done with no change (the code already satisfied it).

## Success rule for every machine run

Use each machine's own **Success rule** (MACHINE.md) verbatim: `rlm.factory.status(run_id)` state `done` AND its
output file present (implement: `outcome.json` with `status: pass`). Anything else (paused, stopped, failed,
`done` without the file) is NOT success. Then: `await rlm.factory.status(run_id)`, `await rlm.factory.stop(run_id)`,
and follow the MACHINE.md instruction (fresh run directory, resize budgets, or escalate to the human). Branch on
status/exit codes, never on prose. Start runs of one machine one at a time (shared pointer file).
A refused `init` (`init.ok` false) goes to `escalate`, which writes no file: it is a non-success run (`done`
without `outcome.json`), retried in a fresh run directory like any other, never a spec block.

**Kinds of `escalated`** (implement `outcome.json` is exactly `{"status": "escalated"}` in every case, so tell
them apart from the node outputs in `await rlm.factory.status(run_id)`): the last `checker` output
`judgement.verdict` is `"TAMPER"` = TAMPER (stop the mission, report to the human); the last `maker` output
`verify.budget` is `"exceeded"` = budget exhausted (attempt or mission limit; stop and report, never raise limits).

## States

1. **SCALE** - `interactive` (one small change, no worktree churn) or `mission` (several tasks, or any
   impact-C change per `agent/rules/impact-scope.md`). Unsure: `mission`.
2. **INIT** - `swarm_adapter.worktree_alloc(slug, scale, cwd=<repo>)` then
   `swarm_adapter.mission_init(slug, goal, scale, cwd=<worktree>)`; stop if either result has `error`/non-zero
   `exit_code`. All later steps use the returned worktree path; keep its `base` sha as the review `base_ref`,
   its `branch` and its `common_dir`.
3. **EXPLORE** - skip for a known, small target. Otherwise run `swarm-explore` with
   `{"question", "roots": [<worktree>]}`; the report is `<run_dir>/report.md`. Read the report, not raw shards.
   Non-success run: a NEW run directory, at most 3 explore runs in total (it has no `budget_guard`); after the
   3rd, stop and report.
4. **PLAN** - write `@fix_plan.md` in the worktree: tasks with id, spec, deps, and the verification commands
   (the repo's own build/test/lint). If the design is ambiguous or touches a shared contract, grill the human
   first (grill-interview rules (read `~/.prime/agent/skills/grill-interview/SKILL.md` if present, else ask the human directly): one question at a time, 2-4 options with a `[Recommended]` badge) and
   record decisions in `CONTEXT.md` before any edit. For an architectural dead end use `prime-swarm-architect`.
5. **EXECUTE** - for each task in dependency order, run `swarm-implement` with
   `{"mission", "task_spec", "worktree", "commands", "test_commands"}`. Size `budget_ms` first if the gate takes
   long (MACHINE.md Residual risks). One task = one run directory.
   - Budget: the machine already calls `swarm_adapter.budget_guard` (5 attempts per run, 20 per mission). If
     `outcome.json` is `escalated`, branch on its kind (above), stop and report; do not raise limits.
   - Non-success run (Success rule fails, the maker may never have run): retry the task in a NEW run directory,
     at most 3 runs per task in total (the same `attempts` limit as `prime-swarm-graph`); after the 3rd, stop
     and report. A retry keeps the same `<tip>`.
   - After `pass`: apply the **Commit rule** above to the mission worktree with `<tip>`. The evidence to show is
     `cs["paths"]` and `st["staged"]`, not the checker prose.
6. **REVIEW** - once all tasks pass, run the **HEAD check** on the mission worktree, then `swarm-review` with
   `{"worktree", "base_ref": <INIT base sha>}`. Run success (Success rule)
   and verdict are separate: read `summary.all_pass` and `summary.failed`. Non-success run: a NEW run directory, at
   most 3 review runs per review round (no `budget_guard` runs there, so no mission budget either); after the 3rd,
   stop and report. Failed lenses become new tasks (back to EXECUTE, max 2 review rounds), then stop and report.
7. **GATE** - run the **HEAD check** again, then present: task outcomes, `change_set(<worktree>, <INIT base>,
   expect_common_dir=<common_dir>)` paths with their `in` states, review summary, residual risks. Then read
   `~/.prime/agent/skills/prime-swarm-release-gate/SKILL.md` and follow it with this `<tip>` as its `<tip>` and the
   INIT `branch` as its `<branch>` (or ask the human to run `/skill:prime-swarm-release-gate` and give them both).
   STOP and wait for the human.

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
