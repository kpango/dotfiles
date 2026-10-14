---
name: prime-swarm-graph
description: DAG variant of the swarm mission for Prime Agent - compiles @fix_plan.md into a dependency graph, runs the ready tasks (at most 3 in parallel) with the swarm-implement machine, replans at most twice, then review and a human gate. Use when the plan has independent tasks that can run in parallel; for strictly sequential work use prime-swarm-loop.
---

# prime-swarm-graph

Same governance, boundaries and per-machine **Success rule** as `prime-swarm-loop`; read that skill's
"Human-only boundaries" and "Success rule" sections first and apply them unchanged. Tier and budget rules live in
`~/.prime/agent/SWARM.md`. This file only adds the DAG scheduling.

Human-only boundaries: no merge, push or deploy without explicit human approval; Tier B governance files (any
`SKILL.md` under `agent/skills`, hooks, `SWARM.md`) are never edited by this skill.

## Steps

1. **INIT / EXPLORE / PLAN** - exactly as in `prime-swarm-loop` (worktree via `swarm_adapter.worktree_alloc`,
   `swarm_adapter.mission_init`, optional `swarm-explore`, `@fix_plan.md` with per-task `deps`).
2. **COMPILE** - `swarm_adapter.graph_compile(plan_path, cwd=<worktree>)`. `graph-compile` is the ONLY authority
   for readiness: never infer the ready set from the plan text or from your memory of what finished. Branch on
   `exit_code`: 0 proceed; 2 `UNFIT_FALLBACK_LOOP` switch to `prime-swarm-loop`; 3 `CYCLE`, 4 `MISSING_DEP`,
   5 `VERIFIER_FLOOR`, 6 `NO_TASKS`, 7 `PARSE_ERROR` fix the plan (that is a replan, see below) or stop.
3. **SCHEDULE** - after every settled task call `swarm_adapter.graph_status(plan_path, cwd=<worktree>)` and
   `swarm_adapter.graph_compile(...)` again; run only the tasks the compile output lists as ready.
   - At most 3 `swarm-implement` runs at once. Each needs its own worktree from `swarm_adapter.worktree_alloc`
     (slug per task) based on the mission branch; the machines share a pointer file, so start one run, wait until
     its `init` settles (`rlm.factory.status`), then start the next.
   - A task is done only by the Success rule (`outcome.json` `status: pass`). Merge a task's worktree into the
     mission worktree only after that, one at a time; a merge conflict is a replan trigger, not something to
     resolve silently. Merging into the mission worktree is allowed; merging toward main is never done here.
4. **REPLAN (max 2)** - triggers: a non-success run you cannot fix by a fresh run directory, a cycle/missing-dep
   compile error, a merge conflict, or a plan found wrong. Update `@fix_plan.md`, recompile, continue. A third
   replan: stop and report to the human. Stale tasks: `graph_compile(..., stale=<id>)` per the script's usage.
5. **REVIEW / GATE** - as `prime-swarm-loop` steps 6-7 (`swarm-review`, read `summary.all_pass`, then
   `Skill(prime-swarm-release-gate)` and STOP for the human).

## Budgets

Per run and per mission limits come from `swarm_adapter.budget_guard` inside the machine (exit_code 1 = exceeded:
stop that task and report). Do not reset counters (`reset=True`) without the human's say-so.
