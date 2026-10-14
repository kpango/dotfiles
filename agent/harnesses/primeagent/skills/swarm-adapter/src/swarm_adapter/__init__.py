"""Thin async adapter over the existing swarm scripts for the prime-agent REPL.

No budget/graph/decide logic lives here: every function shells out to the existing
script and returns a plain dict. Only worktree_alloc and verify are
new, and they are deliberately minimal prime-specific control. No destructive operation lives here:
worktree cleanup is done by the human or agent/skills/swarm-implement/scripts/worktree-release.sh.

Script lookup (per script, first hit wins), derived ONLY from this module's own real path, never from the
environment or the caller's cwd (subprocesses run in the caller's target repo, so anything cwd-relative or
env-overridable would let that repo choose which code the adapter executes):
  1. the dotfiles repo `agent/skills` found by walking up from this file's real path
  2. ~/.claude/skills
"""
from __future__ import annotations

import asyncio
import functools
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
    "worktree_alloc", "verify", "decide_shell",
]

_TAIL = 4000
_REAP = 2.0  # seconds verify waits for output EOF after killing the group, before abandoning the pipe
# git "local" env vars: inherited (e.g. from a git hook) they would redirect every `git -C <cwd>` call.
_GIT_LOCAL_ENV = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
                  "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX", "GIT_NAMESPACE")
_BUDGET = "swarm-implement/scripts/budget-guard.sh"
_COMPILE = "swarm-graph/scripts/graph-compile.sh"
_STATUS = "swarm-graph/scripts/graph-status.sh"
_INIT = "swarm-loop/scripts/mission-init.sh"


@functools.cache
def _repo_agent_dir() -> Path | None:
    """The dotfiles `agent` dir above this module's real path (absolute, resolved once)."""
    for p in Path(__file__).resolve().parents:
        if p.name == "agent" and (p / "skills").is_dir():
            return p
    return None


def _scripts_root(rel: str) -> str:
    """Return the skills root that contains `rel` (or the best candidate if none does)."""
    agent = _repo_agent_dir()
    cands = ([agent / "skills"] if agent else []) + [Path.home() / ".claude" / "skills"]
    return str(next((c for c in cands if (c / rel).is_file()), cands[0]))


def _fail(e: Exception) -> dict[str, Any]:
    return {"exit_code": 1, "stdout": "", "stderr": "", "error": f"{type(e).__name__}: {e}"}


def _boundary(fail=_fail):
    """Contract enforcement point: every public coroutine converts ANY Exception into `fail(e)` (an error dict),
    so "never raises" holds by construction instead of by per-input validation inside each function."""
    def deco(fn):
        @functools.wraps(fn)
        async def wrapper(*a, **kw):
            try:
                return await fn(*a, **kw)
            except Exception as e:
                return fail(e)
        return wrapper
    return deco


def _sync_run(argv: list[str], cwd: str | None = None, stdin: str | None = None,
              timeout: float | None = None, env: dict[str, str] | None = None) -> dict[str, Any]:
    # PYTHONSAFEPATH=1 (defense in depth): no python started by a script puts its cwd (the target repo) on sys.path.
    env = {**(os.environ if env is None else env), "PYTHONSAFEPATH": "1"}
    try:
        p = subprocess.run(argv, cwd=cwd, input=stdin, capture_output=True, text=True,
                           timeout=timeout, errors="replace", env=env)
    except FileNotFoundError as e:
        return {"exit_code": 127, "stdout": "", "stderr": str(e)}
    except subprocess.TimeoutExpired:
        return {"exit_code": 124, "stdout": "", "stderr": f"timeout after {timeout}s"}
    return {"exit_code": p.returncode, "stdout": p.stdout, "stderr": p.stderr}


def _script(rel: str, args: list[str], cwd: str | None = None) -> dict[str, Any]:
    path = Path(_scripts_root(rel)) / rel
    if not path.is_file():
        return {"exit_code": 127, "stdout": "", "stderr": f"script not found: {path}"}
    return _sync_run(["bash", str(path), *args], cwd=cwd)


def _bad_dash(**vals: str | None) -> dict[str, Any] | None:
    """Reject option-looking values so they cannot be parsed as script flags."""
    for k, v in vals.items():
        if isinstance(v, str) and v.startswith("-"):
            return {"exit_code": 2, "stdout": "", "stderr": "", "error": f"{k} must not start with '-': {v!r}"}
    return None


async def _a(fn, *a, **kw):
    return await asyncio.to_thread(fn, *a, **kw)


def _mission(mission: str | None) -> list[str]:
    return [f"--mission={mission}"] if mission else []


@_boundary()
async def budget_guard(task_id: str, mission: str | None = None, max_attempts: int | None = None,
                       mission_max: int | None = None, reset: bool = False) -> dict[str, Any]:
    """Count one attempt for task_id (budget-guard.sh). exit_code 1 = budget exceeded.

    max_attempts is the 2nd positional (script default 5); mission_max -> --mission-max=N;
    reset=True runs `--reset <task> [--mission=m]` instead of counting.
    """
    if (bad := _bad_dash(task_id=task_id, mission=mission)):
        return bad
    if reset:
        return await _a(_script, _BUDGET, ["--reset", task_id, *_mission(mission)])
    args = [task_id] + ([str(max_attempts)] if max_attempts is not None else []) + _mission(mission)
    if mission_max is not None:
        args.append(f"--mission-max={mission_max}")
    return await _a(_script, _BUDGET, args)


@_boundary()
async def fable_grant(task_id: str, mission: str | None = None) -> dict[str, Any]:
    """Request a Fable spot grant (budget-guard.sh --fable). exit_code 1 = denied."""
    if (bad := _bad_dash(task_id=task_id, mission=mission)):
        return bad
    return await _a(_script, _BUDGET, ["--fable", task_id, *_mission(mission)])


@_boundary()
async def fable_maker(task_id: str) -> dict[str, Any]:
    """Fable Maker continuation grant for a base task (budget-guard.sh --fable-maker <base>)."""
    if (bad := _bad_dash(task_id=task_id)):
        return bad
    return await _a(_script, _BUDGET, ["--fable-maker", task_id])


@_boundary()
async def graph_compile(plan_path: str | None = None, fit: bool = False, stale: str | None = None,
                        cwd: str | None = None) -> dict[str, Any]:
    """Compile @fix_plan.md into a DAG (graph-compile.sh).

    Returns the script's parsed JSON plus `exit_code`. Exit codes: 0 OK, 2
    UNFIT_FALLBACK_LOOP, 3 CYCLE, 4 MISSING_DEP, 5 VERIFIER_FLOOR, 6 NO_TASKS,
    7 PARSE_ERROR. Non-JSON output yields {exit_code, stdout, stderr}. Runs in `cwd` (default: process cwd).
    """
    if (bad := _bad_dash(plan_path=plan_path, stale=stale)):
        return bad
    args = (["--fit"] if fit else []) + (["--stale", stale] if stale else []) + ([plan_path] if plan_path else [])
    r = await _a(_script, _COMPILE, args, cwd)
    try:
        parsed = json.loads(r["stdout"])
    except ValueError:
        return r
    if not isinstance(parsed, dict):
        return r
    parsed["exit_code"] = r["exit_code"]
    return parsed


@_boundary()
async def graph_status(plan_path: str | None = None, cwd: str | None = None) -> dict[str, Any]:
    """Human-readable graph mission summary (graph-status.sh). plan_path defaults to <toplevel>/@fix_plan.md; runs in `cwd`."""
    if (bad := _bad_dash(plan_path=plan_path)):
        return bad
    return await _a(_script, _STATUS, [plan_path] if plan_path else [], cwd)


@_boundary()
async def mission_init(slug: str, goal: str, scale: str | None = None, targets: str | None = None,
                       depth: int | None = None, cwd: str | None = None) -> dict[str, Any]:
    """Initialise a mission (mission-init.sh <slug> <goal> <scale> [targets] [depth]), run in `cwd` (the mission worktree).

    scale is 'interactive' or 'mission' (script default 'mission'). stdout = state dir.
    """
    if (bad := _bad_dash(slug=slug)):
        return bad
    args = [slug, goal]
    if scale is not None or targets is not None or depth is not None:
        args.append(scale or "mission")  # script default; keeps later positionals in place
    if targets is not None or depth is not None:
        args.append(targets or "")
    if depth is not None:
        args.append(str(depth))
    return await _a(_script, _INIT, args, cwd)


def _git(cwd: str, *args: str) -> dict[str, Any]:
    env = {k: v for k, v in os.environ.items() if k not in _GIT_LOCAL_ENV}
    return _sync_run(["git", "-C", cwd, *args], env=env)


def _repo_tops(cwd: str) -> tuple[tuple[Path, Path] | None, dict[str, Any] | None]:
    """((main checkout toplevel, caller toplevel), None) or (None, error dict).

    Only the plain layout (common git dir == <main toplevel>/.git) is supported; a submodule or
    --separate-git-dir checkout is refused rather than guessed at."""
    top = _git(cwd, "rev-parse", "--show-toplevel")
    common = _git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if top["exit_code"] != 0 or common["exit_code"] != 0:
        return None, {"exit_code": 128, "error": f"not a git repository: {cwd}"}
    cdir, caller_top = Path(common["stdout"].strip()), Path(top["stdout"].strip())
    main = cdir.parent
    gitdir = _git(cwd, "rev-parse", "--absolute-git-dir")["stdout"].strip()
    # In the main checkout (git dir == common dir) the common dir must be exactly <toplevel>/.git; a
    # --separate-git-dir checkout has a `.git` gitfile there instead (its gitdir may still be *named* .git).
    # Limit: a linked worktree of a --separate-git-dir repo cannot be told apart from layout alone.
    in_main = bool(gitdir) and Path(gitdir).resolve() == cdir.resolve()
    if (cdir.name != ".git" or cdir.resolve() != (main / ".git").resolve()
            or (in_main and (caller_top / ".git").resolve() != cdir.resolve())):
        return None, {"exit_code": 1, "error": f"unsupported repository layout: git common dir {cdir} is not "
                      "<toplevel>/.git (submodule or --separate-git-dir)"}
    return (main, caller_top), None


def _worktree_base(main: Path, caller: Path) -> tuple[Path | None, str]:
    """Worktree root (CONTEXT Q8), absolute and resolved; refuses a location inside the main repo or the caller's checkout."""
    env = os.environ.get("SWARM_WORKTREE_DIR")
    base = (Path(os.path.abspath(env)) if env else main.parent / ".worktrees" / main.name).resolve()
    for top in (main.resolve(), caller.resolve()):
        if base == top or top in base.parents:
            return None, f"worktree dir {base} is inside the repo {top}"
    return base, ""


def _worktree_alloc(slug: str, scale: str | None, cwd: str | None, base_ref: str) -> dict[str, Any]:
    caller = cwd or os.getcwd()
    tops, tops_err = _repo_tops(caller)
    if tops is None:
        return tops_err
    root, caller_top = tops
    base, err = _worktree_base(root, caller_top)
    if base is None:
        return {"exit_code": 1, "error": err}
    sha = _git(caller, "rev-parse", "--verify", "--end-of-options", f"{base_ref}^{{commit}}")
    if sha["exit_code"] != 0:
        return {"exit_code": sha["exit_code"], "error": f"cannot resolve base_ref {base_ref!r}: {sha['stderr'].strip()}"}
    base_sha = sha["stdout"].strip()
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", slug).strip("-") or "mission"
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    path, branch = base / f"{safe}-{ts}", f"swarm-prime/{safe}-{ts}"
    base.mkdir(parents=True, exist_ok=True)
    r = _git(str(root), "worktree", "add", "-b", branch, str(path), base_sha)
    if r["exit_code"] != 0:
        return {"exit_code": r["exit_code"], "error": r["stderr"].strip()}
    return {"path": str(path), "branch": branch, "base": base_sha, "scale": scale, "exit_code": 0}


@_boundary()
async def worktree_alloc(slug: str, scale: str | None = None, cwd: str | None = None,
                         base_ref: str = "HEAD") -> dict[str, Any]:
    """Create a worktree outside the repo (CONTEXT Q8): ${SWARM_WORKTREE_DIR:-<repo parent>/.worktrees/<repo>}/<slug>-<UTC ts>.

    A relative SWARM_WORKTREE_DIR is made absolute against the process cwd; a location inside the repo is refused.
    The branch starts at `base_ref` (default HEAD) resolved in the CALLER's checkout (`cwd`), not the main repo's HEAD.
    Returns {path, branch, base, scale, exit_code} or {exit_code, error}. `cwd` selects the repo (default: process cwd).
    """
    if (bad := _bad_dash(base_ref=base_ref)):
        return bad
    return await _a(_worktree_alloc, slug, scale, cwd, base_ref)


def _killpg(p: subprocess.Popen) -> None:
    try:
        os.killpg(p.pid, signal.SIGKILL)  # whole group: backgrounded grandchildren too
    except ProcessLookupError:  # group already gone (exit race): nothing to kill
        pass


def _text(o: Any) -> str:
    return o.decode(errors="replace") if isinstance(o, bytes) else (o or "")


def _run_gate(c: str, cwd: str, timeout: float) -> dict[str, Any]:
    """One gate command; wall time is bounded by timeout + _REAP even if a descendant escaped the group."""
    p = subprocess.Popen(["bash", "-c", c], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace", start_new_session=True)
    try:
        try:
            out, _ = p.communicate(timeout=timeout)
            return {"command": c, "exit_code": p.returncode, "output_tail": out[-_TAIL:]}
        except subprocess.TimeoutExpired:
            pass
        _killpg(p)
        note = f"\n[swarm-adapter] timeout after {timeout}s; process group killed"
        try:
            out, _ = p.communicate(timeout=_REAP)
        except subprocess.TimeoutExpired as e:  # a descendant that left the group (setsid) still holds the pipe
            out = _text(e.output)
            note += f"; output pipe still held after {_REAP}s by a descendant outside the group (setsid): abandoned"
            rc = p.poll()
            if rc is not None and rc != -signal.SIGKILL:  # the command itself had exited on its own: keep its real code
                return {"command": c, "exit_code": rc, "output_tail": (out + note)[-_TAIL:]}
        return {"command": c, "exit_code": 124, "output_tail": (out + note)[-_TAIL:]}
    except BaseException:  # bad timeout type, KeyboardInterrupt, ...: never leave the gate running
        _killpg(p)
        raise
    finally:
        p.stdout.close()


def _verify(commands: Any, cwd: str, timeout: float) -> dict[str, Any]:
    if isinstance(commands, str):
        commands = [commands]
    if not Path(cwd).is_dir():
        return {"passed": False, "results": [], "error": f"cwd does not exist: {cwd}"}
    results = []
    for c in commands:
        try:
            results.append(_run_gate(c, cwd, timeout))
        except Exception as e:  # per-command: one bad command (null byte, non-str, OSError, ...) must not hide the others
            results.append({"command": c if isinstance(c, str) else repr(c),
                            "exit_code": 127 if isinstance(e, FileNotFoundError) else 126,
                            "output_tail": f"{type(e).__name__}: {e}"[-_TAIL:]})
    return {"passed": bool(results) and all(r["exit_code"] == 0 for r in results), "results": results}


@_boundary(lambda e: {"passed": False, "results": [], "error": f"{type(e).__name__}: {e}"})
async def verify(commands: list[str] | str, cwd: str, timeout: float = 600) -> dict[str, Any]:
    """Run each deterministic gate command via bash in cwd; machine guards branch on `passed`/`exit_code`.

    A bare str is one command. On timeout the whole process group is killed (exit_code 124) and the call returns
    within timeout + 2s per command; a descendant that left the group (setsid) is NOT killed (known limit).
    A missing cwd returns {passed: False, results: [], error}.
    """
    return await _a(_verify, commands, cwd, timeout)


def _block(msg: str) -> dict[str, Any]:
    return {"decision": "block", "reason": "swarm-adapter: " + msg, "error": msg}


_PATTERN_KEYS = ("all_of", "any_of", "any_of_with_branches")


def _rules_ok(path: Path) -> bool:
    """decide.py fails open on a rules file that does not actually block anything. Same criterion as
    agent/scripts/prime-shell-guard.sh (pinned by a parity test): a JSON object whose shell_command_rules list holds at
    least one block-tier rule with a non-empty pattern list."""
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return False
    rules = data.get("shell_command_rules") if isinstance(data, dict) else None
    return isinstance(rules, list) and any(
        isinstance(r, dict) and r.get("tier") == "block"
        and any(isinstance(r.get(k), list) and r[k] for k in _PATTERN_KEYS) for r in rules)


def _decide_shell(command: str, cwd: str | None) -> dict[str, Any]:
    agent = _repo_agent_dir()
    decide = agent / "scripts/hooks/decide.py" if agent else None
    rules = agent / "security-rules.json" if agent else None
    if not (decide and decide.is_file() and rules and rules.is_file()):
        return _block("decide.py/security-rules.json unavailable (fail-closed: this adapter runs without hooks)")
    if not _rules_ok(rules):
        return _block(f"{rules} is not a JSON object with >=1 block-tier shell_command_rules entry that has patterns (fail-closed)")
    # harness "primeagent": prime has no human confirm, so decide.py's advisory layer (which it runs, incl. guard_relax,
    # only for claude/agy/pi) must NOT be able to relax a deterministic decision here.
    req = {"family": "security_shell", "command": command, "cwd": cwd or os.getcwd(),
           "rules_file": str(rules), "resolve_command_target": False, "harness": "primeagent"}
    # decide.py resolves "." / relative `cd`/`-C` targets (e.g. the protected-branch rules) against ITS process cwd,
    # so it must run in the requested cwd; a missing dir surfaces as a failed run -> block (fail-closed).
    r = _sync_run(["python3", "-I", str(decide)], cwd=req["cwd"], stdin=json.dumps(req), timeout=10)
    try:
        out = json.loads(r["stdout"])
    except ValueError:
        out = None
    if r["exit_code"] != 0 or not isinstance(out, dict) or out.get("decision") not in ("allow", "ask", "block"):
        return _block(f"decide.py failed (fail-closed): exit {r['exit_code']} {r['stderr'][:200]}")
    if "fail-open" in str(out.get("reason", "")):
        return _block(f"decide.py replied fail-open: {out.get('reason')}")
    return out


@_boundary(lambda e: _block(f"{type(e).__name__}: {e} (fail-closed)"))
async def decide_shell(command: str, cwd: str | None = None) -> dict[str, Any]:
    """Security decision for a shell command via agent/scripts/hooks/decide.py (run in `cwd`, default process cwd): {decision: allow|ask|block, reason}.

    Fail-closed: if decide.py cannot be found or run, returns decision "block" with an `error` field.
    """
    return await _a(_decide_shell, command, cwd)
