"""Thin async adapter over the existing swarm scripts for the prime-agent REPL.

No budget/graph/decide logic lives here: every function shells out to the existing
script and returns a plain dict. Only worktree_alloc/worktree_release and verify are
new, and they are deliberately minimal prime-specific control.

Script lookup (per script, first hit wins):
  1. $SWARM_SCRIPTS_ROOT  (exclusive when set)
  2. the dotfiles repo `agent/skills` found by walking up from this file's real path
  3. ~/.claude/skills
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

__all__ = [
    "budget_guard", "fable_grant", "graph_compile", "graph_status", "mission_init",
    "worktree_alloc", "worktree_release", "verify", "decide_shell", "scripts_root",
]

_TAIL = 4000
_BUDGET = "swarm-implement/scripts/budget-guard.sh"
_COMPILE = "swarm-graph/scripts/graph-compile.sh"
_STATUS = "swarm-graph/scripts/graph-status.sh"
_INIT = "swarm-loop/scripts/mission-init.sh"


def _repo_agent_dir() -> Path | None:
    for p in Path(__file__).resolve().parents:
        if p.name == "agent" and (p / "skills").is_dir():
            return p
    return None


def scripts_root(rel: str) -> str:
    """Return the skills root that contains `rel` (or the best candidate if none does)."""
    env = os.environ.get("SWARM_SCRIPTS_ROOT")
    if env:
        return env
    agent = _repo_agent_dir()
    cands = ([agent / "skills"] if agent else []) + [Path.home() / ".claude" / "skills"]
    return str(next((c for c in cands if (c / rel).is_file()), cands[0]))


def _sync_run(argv: list[str], cwd: str | None = None, stdin: str | None = None,
              timeout: float | None = None) -> dict[str, Any]:
    try:
        p = subprocess.run(argv, cwd=cwd, input=stdin, capture_output=True, text=True,
                           timeout=timeout, errors="replace")
    except FileNotFoundError as e:
        return {"exit_code": 127, "stdout": "", "stderr": str(e)}
    except subprocess.TimeoutExpired:
        return {"exit_code": 124, "stdout": "", "stderr": f"timeout after {timeout}s"}
    return {"exit_code": p.returncode, "stdout": p.stdout, "stderr": p.stderr}


def _script(rel: str, args: list[str], cwd: str | None = None) -> dict[str, Any]:
    path = Path(scripts_root(rel)) / rel
    if not path.is_file():
        return {"exit_code": 127, "stdout": "", "stderr": f"script not found: {path}"}
    return _sync_run(["bash", str(path), *args], cwd=cwd)


async def _a(fn, *a, **kw):
    return await asyncio.to_thread(fn, *a, **kw)


def _mission(mission: str | None) -> list[str]:
    return [f"--mission={mission}"] if mission else []


async def budget_guard(task_id: str, mission: str | None = None) -> dict[str, Any]:
    """Count one attempt for task_id (budget-guard.sh). exit_code 1 = budget exceeded."""
    return await _a(_script, _BUDGET, [task_id, *_mission(mission)])


async def fable_grant(task_id: str, mission: str | None = None) -> dict[str, Any]:
    """Request a Fable spot grant (budget-guard.sh --fable). exit_code 1 = denied."""
    return await _a(_script, _BUDGET, ["--fable", task_id, *_mission(mission)])


async def graph_compile(plan_path: str, fit: bool = False, stale: str | None = None) -> dict[str, Any]:
    """Compile @fix_plan.md into a DAG (graph-compile.sh).

    Returns the script's parsed JSON plus `exit_code`. Exit codes: 0 OK, 2
    UNFIT_FALLBACK_LOOP, 3 CYCLE, 4 MISSING_DEP, 5 VERIFIER_FLOOR, 6 NO_TASKS,
    7 PARSE_ERROR. Non-JSON output yields {exit_code, stdout, stderr}.
    """
    args = (["--fit"] if fit else []) + (["--stale", stale] if stale else []) + [plan_path]
    r = await _a(_script, _COMPILE, args)
    try:
        parsed = json.loads(r["stdout"])
    except ValueError:
        return r
    if not isinstance(parsed, dict):
        return r
    parsed["exit_code"] = r["exit_code"]
    return parsed


async def graph_status(plan_path: str) -> dict[str, Any]:
    """Human-readable graph mission summary (graph-status.sh)."""
    return await _a(_script, _STATUS, [plan_path])


async def mission_init(slug: str, goal: str, scale: str, targets: str | None = None) -> dict[str, Any]:
    """Initialise a mission (mission-init.sh); scale is 'interactive' or 'mission'. stdout = state dir."""
    return await _a(_script, _INIT, [slug, goal, scale, *([targets] if targets else [])])


def _git(cwd: str, *args: str) -> dict[str, Any]:
    return _sync_run(["git", "-C", cwd, *args])


def _main_repo(cwd: str) -> Path | None:
    r = _git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if r["exit_code"] != 0:
        return None
    common = Path(r["stdout"].strip())
    return common.parent if common.name == ".git" else common


def _worktree_alloc(slug: str, scale: str | None, cwd: str | None) -> dict[str, Any]:
    root = _main_repo(cwd or os.getcwd())
    if root is None:
        return {"exit_code": 128, "error": f"not a git repository: {cwd or os.getcwd()}"}
    base = Path(os.environ.get("SWARM_WORKTREE_DIR") or root.parent / ".worktrees" / root.name)
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", slug).strip("-") or "mission"
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    path, branch = base / f"{safe}-{ts}", f"swarm-prime/{safe}-{ts}"
    base.mkdir(parents=True, exist_ok=True)
    r = _git(str(root), "worktree", "add", "-b", branch, str(path))
    if r["exit_code"] != 0:
        return {"exit_code": r["exit_code"], "error": r["stderr"].strip()}
    return {"path": str(path), "branch": branch, "scale": scale, "exit_code": 0}


async def worktree_alloc(slug: str, scale: str | None = None, cwd: str | None = None) -> dict[str, Any]:
    """Create a worktree outside the repo (CONTEXT Q8): ${SWARM_WORKTREE_DIR:-<repo parent>/.worktrees/<repo>}/<slug>-<UTC ts>.

    Returns {path, branch, scale, exit_code} or {exit_code, error}. `cwd` selects the repo (default: process cwd).
    """
    return await _a(_worktree_alloc, slug, scale, cwd)


def _worktree_release(path: str) -> dict[str, Any]:
    root = _main_repo(path)
    if root is None:
        return {"exit_code": 128, "stdout": "", "stderr": f"not a git worktree: {path}"}
    return _git(str(root), "worktree", "remove", "--force", path)


async def worktree_release(path: str) -> dict[str, Any]:
    """Remove a worktree made by worktree_alloc. The swarm-prime/* branch is kept (it may hold unmerged work)."""
    return await _a(_worktree_release, path)


def _verify(commands: list[str], cwd: str, timeout: float) -> dict[str, Any]:
    results = []
    for c in commands:
        try:
            p = subprocess.run(["bash", "-c", c], cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, timeout=timeout, errors="replace")
            rc, out = p.returncode, p.stdout
        except subprocess.TimeoutExpired as e:
            rc, out = 124, (e.stdout.decode(errors="replace") if isinstance(e.stdout, bytes) else e.stdout or "")
        results.append({"command": c, "exit_code": rc, "output_tail": out[-_TAIL:]})
    return {"passed": bool(results) and all(r["exit_code"] == 0 for r in results), "results": results}


async def verify(commands: list[str], cwd: str, timeout: float = 600) -> dict[str, Any]:
    """Run each deterministic gate command via bash in cwd; machine guards branch on `passed`/`exit_code`."""
    return await _a(_verify, list(commands), cwd, timeout)


def _decide_shell(command: str) -> dict[str, Any]:
    env = os.environ.get("SWARM_AGENT_DIR")
    agent = Path(env) if env else _repo_agent_dir()
    decide = agent / "scripts/hooks/decide.py" if agent else None
    rules = agent / "security-rules.json" if agent else None
    if not (decide and decide.is_file() and rules and rules.is_file()):
        return {"decision": "allow", "reason": "", "error": "decide.py/security-rules.json unavailable (fail-open, as the hook)"}
    req = {"family": "security_shell", "command": command, "cwd": os.getcwd(),
           "rules_file": str(rules), "resolve_command_target": False, "harness": "claude"}
    r = _sync_run(["python3", str(decide)], stdin=json.dumps(req), timeout=10)
    try:
        out = json.loads(r["stdout"])
        if isinstance(out, dict):
            out.setdefault("decision", "allow")
            return out
    except ValueError:
        pass
    return {"decision": "allow", "reason": "", "error": f"decide.py failed (fail-open): {r['stderr'][:200]}"}


async def decide_shell(command: str) -> dict[str, Any]:
    """Security decision for a shell command via agent/scripts/hooks/decide.py: {decision: allow|ask|block, reason}."""
    return await _a(_decide_shell, command)
