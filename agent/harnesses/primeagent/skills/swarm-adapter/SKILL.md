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
```

## Notes

- `graph_compile` exit codes: 0 OK, 2 UNFIT_FALLBACK_LOOP, 3 CYCLE, 4 MISSING_DEP, 5 VERIFIER_FLOOR,
  6 NO_TASKS, 7 PARSE_ERROR. Branch on `verdict`/`exit_code`, never on prose.
- Script root: the dotfiles repo `agent/skills` found from this skill's real path, else `~/.claude/skills`; always absolute. There is NO env
  override (`SWARM_SCRIPTS_ROOT`/`SWARM_AGENT_DIR` were removed): scripts and decide.py run with the caller's target repo as cwd, so a
  cwd-relative or env-chosen path would let that repo make the adapter execute its own code. A missing script yields `exit_code` 127.
- `worktree_alloc` places worktrees outside the repo: `${SWARM_WORKTREE_DIR:-<repo parent>/.worktrees/<repo>}/<slug>-<UTC ts>`,
  branch `swarm-prime/<slug>-<ts>`. A relative `SWARM_WORKTREE_DIR` is made absolute against the process cwd; a location inside the repo is refused.
- The adapter performs NO destructive operation, so there is no release/remove function. Worktree cleanup is done by the human or by
  `agent/skills/swarm-implement/scripts/worktree-release.sh`, outside the agent.
- `verify` runs every command (no short-circuit); a bare str is one command; `passed` is false for an empty list or a missing `cwd`
  (`error` set). `output_tail` is the last 4000 chars of stdout+stderr. A per-command failure to launch (OSError, null byte, non-str element,
  bad `timeout`) is that command's `exit_code` 126/127 and the others still run.
  A timeout kills the whole process group (`exit_code` 124) and the call returns within `timeout` + 2s per command.
  **Known limit:** a descendant that left the group (`setsid`, `set -m`) is not killed; its still-open output pipe is abandoned
  after 2s (the `output_tail` says so) and the process may outlive the call. If the command itself had already exited on its own, its real `exit_code` is reported (not 124) together with that note.
- **Never raises, by construction:** every public function sits behind one `_boundary` wrapper that turns any Exception into
  `{exit_code: 1, stdout: "", stderr: "", error: "<Type>: <msg>"}` (verify: `{passed: false, results: [], error}`; decide_shell:
  `decision: "block"`, `error`). Inputs are therefore not type-checked individually (non-str task ids, `cwd` pointing at a file, ... yield `error`).
- Repo layout: `worktree_alloc` supports only a plain checkout (git common dir resolves to exactly `<toplevel>/.git`, which includes linked
  worktrees of it). A submodule or `--separate-git-dir` checkout is refused (`error` "unsupported repository layout"). The worktree dir may be
  neither inside the main checkout nor inside the caller's checkout. Inherited `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE`/... are
  stripped from every git call (e.g. when run from a git hook).
  Known limit: a *linked* worktree of a `--separate-git-dir` repo is not detected (indistinguishable by layout).
- `graph_compile`/`graph_status`/`mission_init` take `cwd` (default: process cwd).
- `budget_guard(task, mission=, max_attempts=, mission_max=, reset=)` maps to the script's positional/`--mission`/`--mission-max`/`--reset`
  options; `fable_maker(base_task)` is `--fable-maker`. `mission_init(..., depth=, cwd=)` runs in the mission worktree `cwd`.
- `decide_shell(command, cwd=None)` is FAIL-CLOSED: this adapter runs without hooks, so if decide.py or security-rules.json cannot be found
  or run, the result is `decision: "block"` with an `error` field. The agent dir is discovered from this skill's real path (so a symlinked install works).
  It sends harness `"primeagent"`: prime has no human confirm, so decide.py's advisory layer (guard_relax; claude/agy/pi only) must not relax a decision.
- `decide_shell` runs decide.py with its process cwd set to `cwd` (default: process cwd), because the protected-branch rules read the branch of that
  directory; a nonexistent `cwd` yields `block`.
- `decide_shell` also validates `security-rules.json` itself (JSON object, non-empty `shell_command_rules`) and treats any decide.py reply whose
  reason contains `fail-open` as `block`.
- `worktree_alloc(..., base_ref="HEAD")` branches from `base_ref` resolved in the caller's `cwd` checkout (not the main repo HEAD); result has `base` (sha).
- `plan_path` (graph_*) and `scale` (mission_init) are optional like the scripts'; task_id/slug/plan_path/stale/base_ref starting with `-` return an error dict.
- Tests: `uv run --with pytest pytest -q` from this directory.
