---
name: prime-swarm-graph
description: DAG variant of the swarm mission for Prime Agent - compiles @fix_plan.md into a dependency graph, runs the ready tasks (at most 3 in parallel) with the swarm-implement machine, replans at most twice, then review and a human gate. Use when the plan has independent tasks that can run in parallel; for strictly sequential work use prime-swarm-loop.
---

# prime-swarm-graph

Same governance, per-machine **Success rule** and **Commit rule** as `prime-swarm-loop`; read that skill's
"Commit rule" and "Success rule" sections first. Tier and budget rules live in `~/.prime/agent/SWARM.md`. This
file only adds the DAG scheduling.

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

## Steps

1. **INIT / EXPLORE / PLAN** - exactly as in `prime-swarm-loop` (mission worktree via `swarm_adapter.worktree_alloc`,
   `swarm_adapter.mission_init`, optional `swarm-explore`, at most 3 runs). Keep the INIT result's `base` sha: it is the review
   `base_ref`. Plan format: `@fix_plan.md` has a `## Tasks` table with header
   `| task-id | summary | depends | worktree | status | attempts | domain | note |` (as written by
   `agent/skills/swarm-loop/scripts/mission-init.sh`). `graph_compile` reads `depends` and `status`.
2. **COMPILE** - the first compile is the fit check:
   `swarm_adapter.graph_compile(plan_path, fit=True, cwd=<mission worktree>)`. Branch on `exit_code`: 0 proceed;
   2 `UNFIT_FALLBACK_LOOP` (too few tasks or width 1): switch to `prime-swarm-loop` EXECUTE with the same worktree
   and plan; 3 `CYCLE`, 4 `MISSING_DEP`, 5 `VERIFIER_FLOOR`, 6 `NO_TASKS`, 7 `PARSE_ERROR`: fix the plan (a replan,
   step 4) or stop. Later recompiles omit `fit`. `graph_compile` is the ONLY authority for readiness: run only ids
   in its `ready` list, never infer readiness from the plan text or from memory.
3. **SCHEDULE** - status values are exactly the ones `graph-compile.sh` knows: `pending`, `in_progress`, `done`,
   `stale`, `blocked(budget)`, `blocked(design)`, `blocked(spec)`. Edit only the `status`, `worktree`,
   `attempts`, `note` cells, and after EVERY edit recompile and run `graph_status(plan_path, cwd=<mission worktree>)`.
   Write every cell through `cell = lambda s: " ".join(str(s).replace("|", "/").split())[:120]` (one line, no `|`):
   `graph-compile.sh` silently drops a row whose cell count is not 8, so a git error or conflict text with a `|` or
   newline would take the task out of the DAG. After every compile STOP if `warnings` is non-empty (a dropped
   row or an unknown status: fix the plan row first) or if `metrics.nodes` differs from the
   number of rows in the `## Tasks` table (`sum(l.startswith("|") for l in <Tasks section lines>) - 2`, header
   and separator excluded): "all `done`" is only trusted when every plan row is a node.
   - **Start** (at most 3 `swarm-implement` runs at once): task worktree =
     `swarm_adapter.worktree_alloc(slug, cwd=<mission worktree>)` with slug `<task-id>-a<attempts>`, so its base
     is the mission worktree's current HEAD (which already holds every merged upstream task). Every start, retries
     included, allocates a NEW worktree (`worktree_alloc` creates a new `<slug>-<UTC ts>` path and
     `swarm-prime/...` branch; a non-zero `exit_code` is a non-success start). An old task worktree is never reused
     and never removed or deleted by you (human-only cleanup; its path stays in `note`). `<mission tip>` = the
     commit the mission branch must be at: the INIT `worktree_alloc` `base`, then the `c["commit"]` of each merge
     block that finished. Keep it in the REPL next to `<common_dir>`; never take it from a worktree or `@fix_plan.md`.
     If `<mission tip>`, a task's `<tip>` or `<common_dir>` is unknown (REPL or kernel restart, resumed session, ...):
     STOP and ask the human; never re-derive it from HEAD, the commit history, a worktree or `@fix_plan.md`.
     Right after `worktree_alloc` returns, before anything runs in the new worktree, its `base` (the mission HEAD the
     allocation saw) must equal `<mission tip>`; else the mission branch moved outside a merge block: set
     `blocked(design)`, the raw result in `note`, and STOP. Set `in_progress` and the
     `worktree` cell; NEVER start a task that is `in_progress`. The machines share a pointer file: start one run,
     wait until its `init` settles (`rlm.factory.status`), then the next.
   - **Success** (the machine's Success rule holds): in the TASK worktree apply the loop's **Commit rule** (`<tip>` =
     that worktree's `worktree_alloc` `base`, its allocated `branch`, `<common_dir>`); where its Success rule fails, set
     the state it names, the raw result in `note`, and STOP. Then, unless `st["zero_diff"]` (the mission HEAD
     already satisfies the task: no merge), merge one task at a time into the MISSION worktree:
     `inc = await swarm_adapter.incoming(<mission worktree>, <task branch>, expect_common_dir=<common_dir>)` (`<task branch>` = that
     allocated `branch`), then the adapter's merge block with `inc`, both under the same Success rule. Before the
     block, `inc["head"]` must equal `<mission tip>` and `inc["sha"]` must equal that task's `<tip>` (the commit its
     commit block wrote from the worktree the Checker ran on; what the Checker saw there came from git commands, see the
     boundary's residual risk); after it, `vm["head"]` must equal `c["commit"]`. Any mismatch:
     `blocked(design)`, STOP. Then set `<mission tip>` to `c["commit"]`. Set `done`
     only after the merge block finished (or on `zero_diff`), so a downstream worktree cut later contains the
     upstream result. A conflict is an `incoming` `error`, so it follows the Success rule too.
   - **`STOP: update_ref:`** (first time for that task): the mission branch ref did not move (no `update_ref` error
     moves it), but the index and working tree may be left at the merge result (swarm-adapter Notes, `update_ref`)
     and the mission HEAD may have moved since `incoming`. Check before any retry:
     `pre = await swarm_adapter.verify_merge(<mission worktree>, inc["head"], expect_common_dir=<common_dir>)` (old
     head must be an ancestor of the new HEAD; Tier B over the commits between them), then
     `cs = await swarm_adapter.change_set(<mission worktree>, inc["head"], expect_common_dir=<common_dir>)` and
     `swarm_adapter.tier_b_hits(<mission worktree>, list(cs["paths"]), expect_common_dir=<common_dir>)`. Only when
     all three succeed (Success rule), `cs["commits"]` >= 1 and `set(cs["paths"]) - {"@fix_plan.md"}` is within
     `set(pre["paths"])` (nothing but those commits in the index or working tree): re-run `incoming` and the block
     at most once more for that task, with `pre["head"]` in place of `<mission tip>` in the `inc["head"]` check (the
     checks above covered `<mission tip>`..`pre["head"]` and nothing after it). Anything else, any other raise or a
     second one follows the Success rule.
   - **Non-success run** (paused, stopped, failed, `done` without `outcome.json`, which includes a refused
     `init`): `rlm.factory.stop(run_id)`, increment `attempts`, and set the task back to `pending` (it becomes
     ready again; the retry uses a NEW run directory, as MACHINE.md says) while `attempts` < 3. At 3, set
     `blocked(budget)`.
   - **Escalated outcome** (`outcome.json` status `escalated`; tell the kind apart as in `prime-swarm-loop`
     "Kinds of `escalated`"): checker `judgement.verdict` `"TAMPER"`: stop the mission and report to the human;
     maker `verify.budget` `"exceeded"` (attempt or mission limit): `blocked(budget)`. The plan's `task_spec` is
     found wrong (by you or the checker's `checker.md`): `blocked(spec)`; the checker or a spot diagnosis says the
     approach is wrong: `blocked(design)`. Any other `escalated` (neither kind identifiable): `blocked(design)`.
     Reason in `note`; for TAMPER also set `blocked(design)` before stopping, so no task stays `in_progress`.
   - **A STOP with other runs in flight** (any STOP in this skill, among them TAMPER, a Success-rule failure in a
     task's Commit rule or merge block, a tip or branch mismatch, an unknown `<mission tip>`/`<tip>`/`<common_dir>`,
     compile `warnings` or a `metrics.nodes` mismatch, an `update_ref` STOP past its one retry): start no new run; for every other
     `in_progress` task `await rlm.factory.stop(run_id)` and adopt none of its results (no Commit rule, no merge,
     even if its run already finished); set it to `blocked(design)` with the reason in `note`, the same as TAMPER.
     Then STOP and report to the human; only a replan the human approves moves those tasks back to `pending`.
   - **blocked -> pending**: `blocked(spec)`/`blocked(design)` go back to `pending` only through a replan that
     fixes the spec or design (step 4). `blocked(budget)` goes back to `pending` only after the human raises or
     resets the budget; never reset counters yourself.
   - **Stale propagation**: when a `done` task must be redone (its merged result was wrong or its spec changed),
     set it to `pending`, then run `swarm_adapter.graph_compile(plan_path, stale=<task-id>, cwd=<mission worktree>)`
     and set every id in the returned `stale_closure` (done descendants) to `stale`. `stale` tasks are ready again
     once their dependencies are `done`; re-run them like `pending` ones. Stale re-runs are capped by `attempts`
     (its own column, never touched by `note` edits): moving a task to `pending` or `stale` here increments its
     `attempts` first, and at 3 the task goes to `blocked(budget)` instead, and you report to the human.
4. **REPLAN (max 2)** - triggers: a `blocked(spec)`/`blocked(design)` task, a cycle/missing-dep compile error, a
   true deadlock, or a plan found wrong. True deadlock = `ready` is empty AND no task is `in_progress` AND some
   task is not `done` (every remaining task is blocked or waits on a blocked one). An empty `ready` while a task is
   `in_progress` is NOT a trigger: wait for that run to settle. If the remaining blockers are only `blocked(budget)`, a replan cannot help: stop and report. Update `@fix_plan.md` (a replan may add or change rows; outside it
   SCHEDULE edits only the four cells), recompile, continue. A third
   replan: stop and report to the human.
5. **REVIEW / GATE** - when every task is `done`: run the loop's **HEAD check** on the MISSION worktree with
   `<mission tip>` as `<tip>` and the INIT `branch` as the allocated `branch`, then `swarm-review` with
   `{"worktree": <mission worktree>, "base_ref": <INIT base sha>}`
   (the merged task commits are the diff) and read `summary.all_pass` and `summary.failed` (a non-success review run:
   NEW run directory, at most 3 runs per review round, then stop and report; `swarm-review` calls no `budget_guard`).
   Failed lenses are a REPLAN (step 4, counted in its max 2): add one `pending` task row per failed lens, recompile
   and continue at SCHEDULE; the review runs again once every task is `done`. No replan left: stop and report to the
   human. All lenses pass: run the HEAD check again, then read
   `~/.prime/agent/skills/prime-swarm-release-gate/SKILL.md` and follow it with `<mission tip>` as its `<tip>` and
   the INIT `branch` as its `<branch>` (a task's own `<tip>` is never the gate's: it was checked as `inc["sha"]`
   before its merge, and `<mission tip>` is the merge commit that holds it), then STOP for the human.
   A failing gate command (its step 2) or a failed gate step 3 check (HEAD, branch or not-committed paths) is a
   STOP for the human, as the gate says. Only when the human explicitly asks for a fix of failing gate commands is
   it a REPLAN (step 4, counted in its max 2): add one `pending` task row per failing command, recompile and
   continue at SCHEDULE (new task worktrees are cut from `<mission tip>`); REVIEW and the gate run again with the
   new `<mission tip>` once every task is `done`. No replan left: stop and report to the human.

## Budgets

Per run and per mission limits come from `swarm_adapter.budget_guard` inside the machine (exit_code 1 = exceeded:
`blocked(budget)` for that task, report). Do not reset counters (`reset=True`) without the human's say-so.
