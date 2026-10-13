---
name: swarm-adapter
description: Typed async Python API over the existing swarm scripts (budget-guard, graph-compile/status, mission-init, decide.py) plus prime-only worktree allocation and deterministic verify gates. Use from the Python REPL when orchestrating swarm missions; it never re-implements script logic.
---

# Swarm Adapter

Thin kernel-side adapter (CONTEXT Q3): logic stays in the existing scripts, which are
called via subprocess. Every function is async and returns a dict. Call from the REPL:

```python
await swarm_adapter.budget_guard("t1", mission="m")      # {exit_code, stdout, stderr}; exit 1 = budget exceeded
await swarm_adapter.fable_grant("t1", mission="m")       # budget-guard.sh --fable
await swarm_adapter.graph_compile(plan, fit=True)        # parsed JSON + exit_code
await swarm_adapter.graph_status(plan)
await swarm_adapter.mission_init("slug", "goal", "mission", targets=None)
wt = await swarm_adapter.worktree_alloc("slug")          # {path, branch}
await swarm_adapter.verify(["make test"], wt["path"])    # {passed, results[{command, exit_code, output_tail}]}
await swarm_adapter.decide_shell("git status")           # {decision: allow|ask|block, reason}
await swarm_adapter.worktree_release(wt["path"])
```

## Notes

- `graph_compile` exit codes: 0 OK, 2 UNFIT_FALLBACK_LOOP, 3 CYCLE, 4 MISSING_DEP, 5 VERIFIER_FLOOR,
  6 NO_TASKS, 7 PARSE_ERROR. Branch on `verdict`/`exit_code`, never on prose.
- Script root: `$SWARM_SCRIPTS_ROOT` (exclusive when set), else the dotfiles repo `agent/skills`
  (found from this skill's real path), else `~/.claude/skills`. A missing script yields `exit_code` 127.
- `worktree_alloc` places worktrees outside the repo: `${SWARM_WORKTREE_DIR:-<repo parent>/.worktrees/<repo>}/<slug>-<UTC ts>`,
  branch `swarm-prime/<slug>-<ts>`. `worktree_release` removes the worktree but keeps the branch.
- `verify` runs every command (no short-circuit); `passed` is false for an empty list. `output_tail` is the last 4000 chars of stdout+stderr.
- `decide_shell` fails open (like the Claude hook) when decide.py or security-rules.json is unavailable; the result then carries an `error` field.
  `SWARM_AGENT_DIR` overrides the agent dir.
- Tests: `uv run --with pytest pytest -q` from this directory.
