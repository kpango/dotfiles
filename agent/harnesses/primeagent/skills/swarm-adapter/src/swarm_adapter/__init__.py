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
import signal
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

__all__ = [
    "budget_guard", "fable_grant", "fable_maker", "graph_compile", "graph_status", "mission_init",
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


async def budget_guard(task_id: str, mission: str | None = None, max_attempts: int | None = None,
                       mission_max: int | None = None, reset: bool = False) -> dict[str, Any]:
    """Count one attempt for task_id (budget-guard.sh). exit_code 1 = budget exceeded.

    max_attempts is the 2nd positional (script default 5); mission_max -> --mission-max=N;
    reset=True runs `--reset <task> [--mission=m]` instead of counting.
    """
    if reset:
        return await _a(_script, _BUDGET, ["--reset", task_id, *_mission(mission)])
    args = [task_id] + ([str(max_attempts)] if max_attempts is not None else []) + _mission(mission)
    if mission_max is not None:
        args.append(f"--mission-max={mission_max}")
    return await _a(_script, _BUDGET, args)


async def fable_grant(task_id: str, mission: str | None = None) -> dict[str, Any]:
    """Request a Fable spot grant (budget-guard.sh --fable). exit_code 1 = denied."""
    return await _a(_script, _BUDGET, ["--fable", task_id, *_mission(mission)])


async def fable_maker(task_id: str) -> dict[str, Any]:
    """Fable Maker continuation grant for a base task (budget-guard.sh --fable-maker <base>)."""
    return await _a(_script, _BUDGET, ["--fable-maker", task_id])


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


async def mission_init(slug: str, goal: str, scale: str, targets: str | None = None,
                       depth: int | None = None, cwd: str | None = None) -> dict[str, Any]:
    """Initialise a mission (mission-init.sh <slug> <goal> <scale> [targets] [depth]), run in `cwd` (the mission worktree).

    scale is 'interactive' or 'mission'. stdout = state dir.
    """
    args = [slug, goal, scale]
    if targets is not None or depth is not None:
        args.append(targets or "")
    if depth is not None:
        args.append(str(depth))
    return await _a(_script, _INIT, args, cwd)


def _git(cwd: str, *args: str) -> dict[str, Any]:
    return _sync_run(["git", "-C", cwd, *args])


def _main_repo(cwd: str) -> Path | None:
    r = _git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if r["exit_code"] != 0:
        return None
    common = Path(r["stdout"].strip())
    return common.parent if common.name == ".git" else common


def _worktree_base(root: Path) -> tuple[Path | None, str]:
    """Worktree root (CONTEXT Q8), absolute and resolved; refuses a location inside the repo."""
    env = os.environ.get("SWARM_WORKTREE_DIR")
    base = Path(os.path.abspath(env)) if env else root.parent / ".worktrees" / root.name
    base = base.resolve()
    rr = root.resolve()
    if base == rr or rr in base.parents:
        return None, f"worktree dir {base} is inside the repo {rr}"
    return base, ""


def _worktree_alloc(slug: str, scale: str | None, cwd: str | None) -> dict[str, Any]:
    root = _main_repo(cwd or os.getcwd())
    if root is None:
        return {"exit_code": 128, "error": f"not a git repository: {cwd or os.getcwd()}"}
    base, err = _worktree_base(root)
    if base is None:
        return {"exit_code": 1, "error": err}
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

    A relative SWARM_WORKTREE_DIR is made absolute against the process cwd; a location inside the repo is refused.
    Returns {path, branch, scale, exit_code} or {exit_code, error}. `cwd` selects the repo (default: process cwd).
    """
    return await _a(_worktree_alloc, slug, scale, cwd)


def _worktree_branch(root: Path, path: Path) -> str | None:
    out = _git(str(root), "worktree", "list", "--porcelain")["stdout"]
    for block in out.split("\n\n"):
        lines = block.strip().split("\n")
        if lines and lines[0] == f"worktree {path}":
            return next((l[7:] for l in lines if l.startswith("branch ")), None)
    return None


def _worktree_release(path: str) -> dict[str, Any]:
    def refuse(msg: str) -> dict[str, Any]:
        return {"exit_code": 1, "stdout": "", "stderr": "", "error": msg}

    real = Path(path).resolve()
    root = _main_repo(str(real)) if real.is_dir() else None
    if root is None:
        return refuse(f"not a git worktree: {real}")
    base, err = _worktree_base(root)
    if base is None:
        return refuse(err)
    if base not in real.parents:
        return refuse(f"{real} is not under the swarm worktree root {base}")
    branch = _worktree_branch(root, real)
    if branch is None or not branch.startswith("refs/heads/swarm-prime/"):
        return refuse(f"{real} is not a swarm-prime/* worktree (branch: {branch})")
    if _git(str(real), "status", "--porcelain")["stdout"].strip():
        return refuse(f"worktree {real} is dirty; commit or discard changes first")
    return _git(str(root), "worktree", "remove", str(real))


async def worktree_release(path: str) -> dict[str, Any]:
    """Remove a swarm worktree. Refuses (exit_code != 0, `error`) unless the real path is under the worktree root,
    its branch is swarm-prime/*, and it is clean. The branch is kept (it may hold unmerged work)."""
    return await _a(_worktree_release, path)


def _verify(commands: list[str], cwd: str, timeout: float) -> dict[str, Any]:
    if isinstance(commands, str):
        commands = [commands]
    if not Path(cwd).is_dir():
        return {"passed": False, "results": [], "error": f"cwd does not exist: {cwd}"}
    results = []
    for c in commands:
        p = subprocess.Popen(["bash", "-c", c], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, errors="replace", start_new_session=True)
        try:
            out, _ = p.communicate(timeout=timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)  # whole group: backgrounded grandchildren too
            out, _ = p.communicate()
            rc = 124
        results.append({"command": c, "exit_code": rc, "output_tail": out[-_TAIL:]})
    return {"passed": bool(results) and all(r["exit_code"] == 0 for r in results), "results": results}


async def verify(commands: list[str] | str, cwd: str, timeout: float = 600) -> dict[str, Any]:
    """Run each deterministic gate command via bash in cwd; machine guards branch on `passed`/`exit_code`.

    A bare str is one command. On timeout the whole process group is killed (exit_code 124).
    A missing cwd returns {passed: False, results: [], error}.
    """
    return await _a(_verify, commands, cwd, timeout)


def _block(msg: str) -> dict[str, Any]:
    return {"decision": "block", "reason": "swarm-adapter: " + msg, "error": msg}


def _decide_shell(command: str, cwd: str | None) -> dict[str, Any]:
    env = os.environ.get("SWARM_AGENT_DIR")
    agent = Path(env) if env else _repo_agent_dir()
    decide = agent / "scripts/hooks/decide.py" if agent else None
    rules = agent / "security-rules.json" if agent else None
    if not (decide and decide.is_file() and rules and rules.is_file()):
        return _block("decide.py/security-rules.json unavailable (fail-closed: this adapter runs without hooks)")
    # harness stays "claude": decide.py only enables its advisory layer for known harnesses
    # (claude/agy/pi); an unknown value would silently skip it.
    req = {"family": "security_shell", "command": command, "cwd": cwd or os.getcwd(),
           "rules_file": str(rules), "resolve_command_target": False, "harness": "claude"}
    r = _sync_run(["python3", str(decide)], stdin=json.dumps(req), timeout=10)
    try:
        out = json.loads(r["stdout"])
    except ValueError:
        out = None
    if r["exit_code"] != 0 or not isinstance(out, dict) or out.get("decision") not in ("allow", "ask", "block"):
        return _block(f"decide.py failed (fail-closed): exit {r['exit_code']} {r['stderr'][:200]}")
    return out


async def decide_shell(command: str, cwd: str | None = None) -> dict[str, Any]:
    """Security decision for a shell command via agent/scripts/hooks/decide.py: {decision: allow|ask|block, reason}.

    Fail-closed: if decide.py cannot be found or run, returns decision "block" with an `error` field.
    """
    return await _a(_decide_shell, command, cwd)
