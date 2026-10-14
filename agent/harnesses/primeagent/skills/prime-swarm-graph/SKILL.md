---
name: prime-swarm-graph
description: DAG variant of the swarm mission for Prime Agent - compiles @fix_plan.md into a dependency graph, runs the ready tasks (at most 3 in parallel) with the swarm-implement machine, replans at most twice, then review and a human gate. Use when the plan has independent tasks that can run in parallel; for strictly sequential work use prime-swarm-loop.
---

# prime-swarm-graph

Same governance and per-machine **Success rule** as `prime-swarm-loop`; read that skill's "Human-only boundaries"
and "Success rule" sections first. Tier and budget rules live in `~/.prime/agent/SWARM.md`. This file only adds
the DAG scheduling.

Human-only boundaries: merging into or pushing to the user's main branch or any remote, and any deploy, are
human-only. Merging a task worktree branch into the mission worktree is orchestrator work and allowed (step 3).
Tier B governance files are never edited by this skill. Protected (Tier B) paths come from
the dotfiles `agent/write-scope-rules.json` (located as in prime-swarm-loop, never the target repo's copy); apply the write-scope check in `~/.prime/agent/skills/prime-swarm-loop/SKILL.md`
before ANY file edit (prompt contract, no write hook in prime).

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
   - **Start** (at most 3 `swarm-implement` runs at once): task worktree =
     `swarm_adapter.worktree_alloc(slug, cwd=<mission worktree>)` with slug `<task-id>-a<attempts>`, so its base
     is the mission worktree's current HEAD (which already holds every merged upstream task). Every start, retries
     included, allocates a NEW worktree (`worktree_alloc` creates a new `<slug>-<UTC ts>` path and
     `swarm-prime/...` branch; a non-zero `exit_code` is a non-success start). An old task worktree is never reused
     and never removed or deleted by you (human-only cleanup; its path stays in `note`). Set `in_progress` and the
     `worktree` cell; NEVER start a task that is `in_progress`. The machines share a pointer file: start one run,
     wait until its `init` settles (`rlm.factory.status`), then the next.
   - **Success** (the machine's Success rule holds): the maker does not commit. In the TASK worktree first run the
     commit check of the loop's write-scope snippet on `changed(<task worktree>)`: any protected (Tier B) path
     means NO commit and NO merge; set `blocked(spec)` (the spec led the maker into Tier B), the paths in `note`,
     and stop and report to the human. Then stage every path in `changed` by name and
     `git commit -m "<task-id>: <summary>"`; that is exactly what the checker judged (`git diff <init.base>` plus
     untracked files). Zero-diff PASS (`changed` empty and `git rev-list --count HEAD..<task branch>` in the MISSION
     worktree is 0; the mission HEAD already satisfies the task): no commit (it would exit 1) and no merge (it
     would report "Already up to date" and create nothing), set `done` directly. Otherwise, one merge at a
     time, in the MISSION worktree:
     `git merge --no-ff <task branch>`. Set `done` only after that merge commit exists, or after a zero-diff PASS,
     so a downstream worktree cut later contains the upstream result. A failed commit or a merge that fails for a
     reason other than a conflict (or a `decide_shell` `block`/`ask`): `git merge --abort` if one is open, set
     `blocked(design)`, the error in `note`, and report. A merge conflict: `git merge --abort` (the mission worktree is back
     at its pre-merge HEAD), increment `attempts`, put the conflict and the old task worktree path in `note`, and
     set the task back to `pending` while `attempts` < 3 (at 3: `blocked(budget)`). Its next start cuts a NEW
     worktree from the mission HEAD, which now holds the conflicting upstream change, and re-runs the task in a
     NEW run directory. Run these git commands through `swarm_adapter.decide_shell`.
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
   - **blocked -> pending**: `blocked(spec)`/`blocked(design)` go back to `pending` only through a replan that
     fixes the spec or design (step 4). `blocked(budget)` goes back to `pending` only after the human raises or
     resets the budget; never reset counters yourself.
   - **Stale propagation**: when a `done` task must be redone (its merged result was wrong or its spec changed),
     set it to `pending`, then run `swarm_adapter.graph_compile(plan_path, stale=<task-id>, cwd=<mission worktree>)`
     and set every id in the returned `stale_closure` (done descendants) to `stale`. `stale` tasks are ready again
     once their dependencies are `done`; re-run them like `pending` ones.
4. **REPLAN (max 2)** - triggers: a `blocked(spec)`/`blocked(design)` task, a cycle/missing-dep compile error, a
   true deadlock, or a plan found wrong. True deadlock = `ready` is empty AND no task is `in_progress` AND some
   task is not `done` (every remaining task is blocked or waits on a blocked one). An empty `ready` while a task is
   `in_progress` is NOT a trigger: wait for that run to settle. If the remaining blockers are only `blocked(budget)`, a replan cannot help: stop and report. Update `@fix_plan.md`, recompile, continue. A third
   replan: stop and report to the human.
5. **REVIEW / GATE** - when every task is `done`: as `prime-swarm-loop` steps 6-7, running `swarm-review` with
   `{"worktree": <mission worktree>, "base_ref": <INIT base sha>}` (the merged task commits are the diff), read
   `summary.all_pass` (a non-success review run: NEW run directory, at most 3 runs per review round, then stop
   and report; `swarm-review` calls no `budget_guard`), then read `~/.prime/agent/skills/prime-swarm-release-gate/SKILL.md` and follow it, then
   STOP for the human.

## Budgets

Per run and per mission limits come from `swarm_adapter.budget_guard` inside the machine (exit_code 1 = exceeded:
`blocked(budget)` for that task, report). Do not reset counters (`reset=True`) without the human's say-so.
