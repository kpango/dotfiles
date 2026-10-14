---
name: prime-swarm-graph
description: DAG variant of the swarm mission for Prime Agent - compiles @fix_plan.md into a dependency graph, runs the ready tasks (at most 3 in parallel) with the swarm-implement machine, replans at most twice, then review and a human gate. Use when the plan has independent tasks that can run in parallel; for strictly sequential work use prime-swarm-loop.
---

# prime-swarm-graph

Same governance, boundaries and per-machine **Success rule** as `prime-swarm-loop`; read that skill's
"Human-only boundaries" and "Success rule" sections first and apply them unchanged. Tier and budget rules live in
`~/.prime/agent/SWARM.md`. This file only adds the DAG scheduling.

Human-only boundaries: no merge, push or deploy without explicit human approval; Tier B governance files are never edited by this skill.
Protected (Tier B) paths come from `agent/write-scope-rules.json`; apply the write-scope check in
`~/.prime/agent/skills/prime-swarm-loop/SKILL.md` before ANY file edit (prompt contract, no write hook in prime).

## Steps

1. **INIT / EXPLORE / PLAN** - exactly as in `prime-swarm-loop` (worktree via `swarm_adapter.worktree_alloc`,
   `swarm_adapter.mission_init`, optional `swarm-explore`, `@fix_plan.md` with per-task `deps`).
   Plan format: `@fix_plan.md` has a `## Tasks` table with header
   `| task-id | summary | depends | worktree | status | attempts | domain | note |` (as written by
   `agent/skills/swarm-loop/scripts/mission-init.sh`). `graph_compile` reads `depends` and `status`.
2. **COMPILE** - `swarm_adapter.graph_compile(plan_path, cwd=<worktree>)`. `graph-compile` is the ONLY authority
   for readiness: never infer the ready set from the plan text or from your memory of what finished. Branch on
   `exit_code`: 0 proceed; 2 `UNFIT_FALLBACK_LOOP` switch to `prime-swarm-loop`; 3 `CYCLE`, 4 `MISSING_DEP`,
   5 `VERIFIER_FLOOR`, 6 `NO_TASKS`, 7 `PARSE_ERROR` fix the plan (that is a replan, see below) or stop.
3. **SCHEDULE** - run only tasks the compile output lists as ready. Status discipline in the `status` column:
   - set `in_progress` (with `worktree`) when a task's machine run starts; NEVER start a task that is `in_progress`;
   - set `done` only when the machine's Success rule holds (`outcome.json` `status: pass`);
   - otherwise set `blocked` with the `attempts` count and the reason in `note`;
   - after EVERY update re-run `swarm_adapter.graph_compile(...)` (and `graph_status(plan_path, cwd=<worktree>)`).
   - At most 3 `swarm-implement` runs at once. Each task worktree comes from
     `swarm_adapter.worktree_alloc(slug, cwd=<mission worktree>)` so its `base` is the mission branch. The
     machines share a pointer file: start one run, wait until its `init` settles (`rlm.factory.status`), then
     the next.
   - Merging a finished task worktree back into the MISSION worktree is internal and allowed (one at a time,
     only after `done`; a conflict is a replan trigger). Merge or push to the user's main branch or any
     remote is human-only and never done here.
4. **REPLAN (max 2)** - triggers: a non-success run you cannot fix by a fresh run directory, a cycle/missing-dep
   compile error, a merge conflict, or a plan found wrong. Update `@fix_plan.md`, recompile, continue. A third
   replan: stop and report to the human. Stale tasks: `graph_compile(..., stale=<id>)` per the script's usage.
5. **REVIEW / GATE** - as `prime-swarm-loop` steps 6-7 (`swarm-review`, read `summary.all_pass`, then
   read `~/.prime/agent/skills/prime-swarm-release-gate/SKILL.md` and follow it, then STOP for the human).

## Budgets

Per run and per mission limits come from `swarm_adapter.budget_guard` inside the machine (exit_code 1 = exceeded:
stop that task and report). Do not reset counters (`reset=True`) without the human's say-so.
