"""Thin async adapter over the existing swarm scripts for the prime-agent REPL.

No budget/graph/decide logic lives here: every function shells out to the existing
script and returns a plain dict. The prime-specific control (CONTEXT Q3-a) is new and deliberately minimal:
worktree_alloc, verify, and, because prime has no write hook, the commit/merge-time replacement for the
Claude-side write-time guard: change_set, tier_b_hits (agent/write-scope-rules.json, which declares itself
cross-impl fnmatch data), stage_task and incoming, plus the commit/merge steps commit_tree and update_ref (git porcelain run
in the target repository reads config a maker can write, so these steps cannot be left to the caller's own git).
budget-guard, graph-compile and decide.py are never re-implemented.
No destructive operation lives here (no push/reset/rewind; stage_task only updates the index, commit_tree only writes an object,
update_ref only fast-forwards a swarm-prime/* branch by one new commit, compare-and-swap):
worktree cleanup is done by the human or agent/skills/swarm-implement/scripts/worktree-release.sh.

Script lookup (per script, first hit wins), derived ONLY from this module's own real path, never from the
environment or the caller's cwd (subprocesses run in the caller's target repo, so anything cwd-relative or
env-overridable would let that repo choose which code the adapter executes):
  1. the dotfiles repo `agent/skills` found by walking up from this file's real path
  2. ~/.claude/skills
"""
from __future__ import annotations

import asyncio
import contextlib
import fnmatch
import functools
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

__all__ = [
    "budget_guard", "fable_grant", "fable_maker", "graph_compile", "graph_status", "mission_init",
    "worktree_alloc", "verify", "decide_shell", "change_set", "tier_b_hits", "stage_task", "incoming", "verify_merge",
    "commit_tree", "update_ref",
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
    return {"path": str(path), "branch": branch, "base": base_sha, "scale": scale,
            "common_dir": str((root / ".git").resolve()), "exit_code": 0}


@_boundary()
async def worktree_alloc(slug: str, scale: str | None = None, cwd: str | None = None,
                         base_ref: str = "HEAD") -> dict[str, Any]:
    """Create a worktree outside the repo (CONTEXT Q8): ${SWARM_WORKTREE_DIR:-<repo parent>/.worktrees/<repo>}/<slug>-<UTC ts>.

    A relative SWARM_WORKTREE_DIR is made absolute against the process cwd; a location inside the repo is refused.
    The branch starts at `base_ref` (default HEAD) resolved in the CALLER's checkout (`cwd`), not the main repo's HEAD.
    Returns {path, branch, base, scale, common_dir, exit_code} (`common_dir` = the repo's git common dir, what the
    commit/merge-time primitives take as `expect_common_dir`) or {exit_code, error}. `cwd` selects the repo (default: process cwd).
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


# ---- commit/merge-time primitives (CONTEXT Q3-a): prime has no write hook ------------------------------------
_HEX = re.compile(r"[0-9a-f]{7,40}")
_SHA = re.compile(r"[0-9a-f]{40}")
_WS_KEYS = ("suffix_patterns", "fixed_absolute_path_patterns")
_TIER_B_REFUSED = 3  # stage_task exit_code when Tier B paths changed (nothing staged)
# STRUCTURE (T6c attempt 11): no git command of the primitives runs in the target repository. A maker can write everything git
# reads there besides the objects: the working tree and the git dir it shares with the caller (config, hooks/, info/*, refs,
# shallow, commondir, derived object caches). Switching the dangerous parts off one setting at a time kept missing one (a7: a
# filter driver named `x=y`; a10: a promisor remote whose `uploadpack` runs when an object is missing). Instead:
#   location: `_locate` (Python only): `<wt>/.git` (directory, or gitfile -> admin dir -> `commondir` + `gitdir` back link), pinned
#             to the caller's `expect_common_dir`; the repository format is PARSED from <common>/config (never executed): a sha256
#             (`extensions.objectFormat`) or reftable (`extensions.refStorage`, a `reftable` dir) repository, and a shallow one
#             (`<common>/shallow`: the shadow has no shallow list, so ancestry answers could differ), are errors.
#   refs:     read by Python (`_head`, `_ref`): `<gitdir>/HEAD`, loose `refs/heads/*`, `packed-refs`; symrefs followed (at most 5
#             hops), every value a 40-hex sha. git is only ever given a sha, and the shadow has no ref a name could resolve to.
#   git:      every command runs in a private bare SHADOW repository (`_open`: mkdtemp, a config the adapter writes, no hooks, no
#             info/attributes, no refs; info/exclude is a copy of the real one: patterns, data only) with the environment of
#             `_senv`: GIT_DIR=<shadow>, GIT_OBJECT_DIRECTORY=<real objects> (objects and the alternates they list are read there,
#             new objects written there; config is read from GIT_DIR only, measured with GIT_TRACE2_CONFIG_PARAMS),
#             GIT_INDEX_FILE=<real index> unless a private one is named, GIT_CONFIG_NOSYSTEM, GIT_CONFIG_GLOBAL=/dev/null,
#             HOME/XDG_CONFIG_HOME=an empty dir, GIT_NO_LAZY_FETCH (a missing object is an error, never a fetch; git >= 2.45,
#             checked), GIT_NO_REPLACE_OBJECTS, GIT_GRAFT_FILE=/dev/null, GIT_ATTR_SOURCE=<empty tree>, every other inherited
#             GIT_* dropped (GIT_TRACE*, GIT_AUTHOR_*, GIT_COMMITTER_* kept), and the GIT_CONFIG_COUNT pairs below (defense in depth:
#             the shadow config has none of those keys anyway). The binary is exec'd by its absolute path (`_git_exe`: resolved once
#             per process over the absolute PATH entries only; refused if it lies in the checkout, the main checkout or the temp dir),
#             always with cwd = the call's tmp dir (also with GIT_WORK_TREE) and a PATH without relative entries (T6c a12).
#   working tree: listed and read by Python (`_scan`: os.scandir, symlinks never followed, a nested repository refused; `_blob`);
#             new blobs are written by `hash-object -w --no-filters --stdin-paths` from private copies. Two commands read it, both
#             in the shadow with GIT_WORK_TREE (no config/attributes there can name a command): `check-ignore --no-index` (the
#             .gitignore files) and update_ref(checkout=True)'s `read-tree -m -u` (git's own "would be overwritten" checks).
#   objects:  NOT trusted (T6c a17). A maker can write the shared object store: a loose object file, a pack/.idx pair or an
#             objects/info/alternates entry that serves other content under an existing oid. git checks the hash only of an
#             object it parses with parse_object (a root tree named on the command line: "hash mismatch"), NOT of the subtrees
#             diff-tree / ls-tree -r / merge-tree read below it nor of a blob it reads (measured, git 2.54: a base subtree
#             replaced by the task's own subtree made the Tier B change vanish from every diff; `git fsck` reports it as
#             "hash-path mismatch" / "packed ... is corrupt"). So every object a check reads is re-hashed by Python first
#             (`_verify_objects`: `cat-file --batch`, the same lookup git uses for loose, packed and alternates objects):
#             the commits named, every tree they reach, the blobs on both sides of each diff and every symlink blob.
#             Derived caches are off: core.commitGraph=false, core.multiPackIndex=false.
# Measured (GIT_TRACE2_EVENT, pinned by tests): 0 child_start events in all seven primitives (and the SKILL.md commit/merge blocks)
# while hooks, core.* commands, filter/diff/merge drivers selected by <common dir>/info/attributes, include.path, a promisor
# remote (`uploadpack`) with refs/HEAD pointing at missing commits, and a tampered objects/info/alternates all hold a trap; the same
# git commands run against the real repository start children (negative controls).
# These are hardening only: the invariant that makes stage_task safe is its final check of the tree it returns.
_EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"  # built into git, never needs writing
_MIN_GIT = (2, 45)  # GIT_NO_LAZY_FETCH (2.45), GIT_ATTR_SOURCE (2.40)
_GIT_VERSION: list[tuple[int, int]] = []  # parsed once per process
_GIT_EXE: list[str] = []  # the git binary's absolute path, resolved once per process (`_git_exe`)
_KEEP_GIT_ENV = ("GIT_TRACE", "GIT_AUTHOR_", "GIT_COMMITTER_")
_NO_DISTORT_ENV = {"GIT_NO_REPLACE_OBJECTS": "1", "GIT_GRAFT_FILE": os.devnull, "GIT_ATTR_SOURCE": _EMPTY_TREE,
                   "GIT_NO_LAZY_FETCH": "1", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
_NO_DISTORT_CONFIG = (("advice.graftFileDeprecated", "false"), ("core.attributesFile", os.devnull), ("core.fsmonitor", "false"),
                      ("diff.ignoreSubmodules", "none"), ("core.commitGraph", "false"), ("core.multiPackIndex", "false"),
                      ("core.hooksPath", os.devnull), ("gc.auto", "0"), ("maintenance.auto", "false"))
_SHADOW_CONFIG = "[core]\n\trepositoryformatversion = 0\n\tbare = true\n"
_SYMREF_HOPS = 5  # git's SYMREF_MAXDEPTH
_BAD_REF = re.compile(r"[\x00-\x20\x7f~^:?*\[\\]|\.\.|@\{|//|/\.|\.lock(?:/|$)|^[/.]|[/.]$")


def _ref_ok(name: str) -> bool:
    """`git check-ref-format` rules (strict subset): no control/space/~^:?*[\\, no `..`, `@{`, empty or dot-leading component,
    `.lock` component suffix, leading/trailing `/` or `.`. A name that passes is also a safe relative path under the git dir."""
    return isinstance(name, str) and name not in ("", "@") and not _BAD_REF.search(name)


def _read_file(path: str, cap: int = 1 << 20, *, dir_fd: int | None = None, follow: bool = False) -> bytes | None:
    """A small regular file's bytes; None if it is absent or a directory. Without `follow` it is opened O_NOFOLLOW (a symlink
    raises); a FIFO/device or a file over `cap` bytes raises (O_NONBLOCK: never blocks)."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | (0 if follow else os.O_NOFOLLOW), dir_fd=dir_fd)
    except (FileNotFoundError, NotADirectoryError):
        return None
    try:
        mode = os.fstat(fd).st_mode
        if stat.S_ISDIR(mode):
            return None
        if not stat.S_ISREG(mode):
            raise OSError(f"{path}: not a regular file")
        chunks, n = [], 0
        while (b := os.read(fd, cap + 1 - n)) and n <= cap:
            chunks.append(b)
            n += len(b)
    finally:
        os.close(fd)
    if n > cap:
        raise OSError(f"{path}: larger than {cap} bytes")
    return b"".join(chunks)


_CFG_SECTION = re.compile(r'\s*\[\s*([A-Za-z0-9.-]+)(?:\s+"((?:[^"\\]|\\.)*)")?\s*\](.*)')
_CFG_KEY = re.compile(r"\s*([A-Za-z][A-Za-z0-9-]*)\s*(?:=(.*))?")


def _cfg_value(v: str) -> str:
    out, quoted, i = [], False, 0
    while i < len(v):
        c = v[i]
        if c == '"':
            quoted = not quoted
        elif c == "\\":
            i += 1
            esc = {"n": "\n", "t": "\t", "b": "\b", "\\": "\\", '"': '"'}.get(v[i:i + 1])
            if esc is None:
                raise ValueError(f"bad escape in config value {v!r}")
            out.append(esc)
        elif c in "#;" and not quoted:
            break
        else:
            out.append(c)
        i += 1
    if quoted:
        raise ValueError(f"unterminated quote in config value {v!r}")
    return "".join(out).strip()


def _config_values(text: str, strict: bool = True) -> dict[str, str]:
    """Parse a git config file (no includes): {"section.key" / "section.subsection.key": last value}, section and key lowercased.
    `strict`: an unparseable line raises ValueError (fail-closed for the repository format); else it is skipped."""
    out: dict[str, str] = {}
    sec, lines = None, text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        while line.endswith("\\") and not line.endswith("\\\\") and i + 1 < len(lines):  # value continued on the next line
            i += 1
            line = line[:-1] + lines[i]
        i += 1
        try:
            if (m := _CFG_SECTION.fullmatch(line)):
                name, sub, line = m.groups()
                sec = name.lower() + ("." + re.sub(r"\\(.)", r"\1", sub) if sub is not None else "")
            if not line.strip() or line.lstrip()[:1] in ("#", ";"):
                continue
            if sec is None or not (k := _CFG_KEY.fullmatch(line)):
                raise ValueError(f"unparseable config line {line[:80]!r}")
            out[f"{sec}.{k[1].lower()}"] = "true" if k[2] is None else _cfg_value(k[2])
        except ValueError:
            if strict:
                raise
    return out


def _repo_format(common: str) -> str:
    """"" or why the repository at git common dir `common` is not supported (parsed from files, nothing executed)."""
    data = _read_file(os.path.join(common, "config"))
    vals = _config_values(os.fsdecode(data or b""))
    if (fmt := vals.get("extensions.objectformat", "sha1").lower()) != "sha1":
        return f"object format {fmt!r} is not supported (sha1 only)"
    if vals.get("extensions.refstorage", "files").lower() != "files" or os.path.lexists(os.path.join(common, "reftable")):
        return "the reftable ref backend is not supported (files only)"
    if os.path.lexists(os.path.join(common, "shallow")):
        return "a shallow repository is not supported (the shadow repository has no shallow list: ancestry answers could differ)"
    return ""


@dataclass
class _R:
    """A checkout located by Python: `top` its top level, `gitdir` its admin dir, `common` the git common dir, `main` the main
    checkout (parent of `common`); once opened, `tmp` holds the call's private shadow repository `sh` and an empty `home`.
    `verified`: {oid: type} of the objects `_verify_objects` re-hashed in this call; `spent`: [objects, bytes] it read."""
    top: str
    gitdir: str
    common: str
    main: str
    tmp: str = ""
    verified: dict[str, str] = field(default_factory=dict)
    spent: list[int] = field(default_factory=lambda: [0, 0])

    @property
    def sh(self) -> str:
        return os.path.join(self.tmp, "shadow.git")


def _locate(wt: Any, expect: Any) -> tuple[_R | None, dict[str, Any] | None]:
    """(checkout, None) or (None, error): Python only, git is not run. `wt` must be the top level of the main checkout (`.git` a real
    directory) or of a linked worktree (`.git` a gitfile naming `<common>/worktrees/<n>`, whose `gitdir` file names this `.git`
    back) of the repository whose common dir is `expect` (the maker owns `<wt>/.git`: a gitfile repointed at a decoy clone would make
    every later read answer for the decoy). Plain layout only: the common dir is `<main>/.git`. A symlinked `.git` is refused."""
    if not (isinstance(expect, str) and expect and os.path.isabs(expect)):
        return None, {"exit_code": 2, "error": "expect_common_dir is required: the absolute git common dir of the repository "
                      "the caller allocated (worktree_alloc's `common_dir`), so a redirected <wt>/.git cannot go unnoticed"}
    top = os.path.abspath(wt)
    dotgit = os.path.join(top, ".git")
    try:
        st = os.lstat(dotgit)
    except (FileNotFoundError, NotADirectoryError):
        if not os.path.isdir(top):
            return None, {"exit_code": 128, "error": f"not a git repository: {wt}"}
        return None, {"exit_code": 1, "error": f"{wt} is not a worktree top level (it has no .git entry)"}
    if stat.S_ISLNK(st.st_mode):
        return None, {"exit_code": 1, "error": f"{dotgit} is a symlink (the repository of {wt} must not be redirected)"}
    back_ok = True
    if stat.S_ISDIR(st.st_mode):  # main checkout: .git is the common dir itself
        gitdir = common = os.path.realpath(dotgit)
        if os.path.lexists(os.path.join(gitdir, "commondir")):
            return None, {"exit_code": 1, "error": f"unsupported repository layout: {dotgit}/commondir exists"}
    else:  # linked worktree
        m = re.fullmatch(rb"gitdir: (.+?)\r?\n?", _read_file(dotgit, 4096) or b"")
        if not m:
            return None, {"exit_code": 1, "error": f"{dotgit} is not a gitfile"}
        gitdir = os.path.realpath(os.path.join(top, os.fsdecode(m[1])))
        cd = _read_file(os.path.join(gitdir, "commondir"), 4096)
        if cd is None:
            return None, {"exit_code": 1, "error": f"{gitdir} is not a linked worktree admin dir (no commondir)"}
        common = os.path.realpath(os.path.join(gitdir, os.fsdecode(cd.rstrip(b"\r\n"))))
        back = _read_file(os.path.join(gitdir, "gitdir"), 4096)
        back_ok = (back is not None and os.path.dirname(gitdir) == os.path.join(common, "worktrees")
                   and os.path.realpath(os.path.join(gitdir, os.fsdecode(back.rstrip(b"\r\n")))) == os.path.realpath(dotgit))
    if common != os.path.realpath(expect):
        return None, {"exit_code": 1, "error": f"{wt} belongs to the repository {common}, not the expected {os.path.realpath(expect)}"}
    if not back_ok:
        return None, {"exit_code": 1, "error": f"{wt}: git dir {gitdir} is not this checkout's own admin dir of {common}"}
    main = os.path.dirname(common)
    if os.path.basename(common) != ".git" or not os.path.isdir(os.path.join(main, ".git")) or \
            os.path.islink(os.path.join(main, ".git")) or os.path.realpath(os.path.join(main, ".git")) != common:
        return None, {"exit_code": 1, "error": f"unsupported repository layout: git common dir {common} is not <main checkout>/.git"}
    if (e := _repo_format(common)):
        return None, {"exit_code": 1, "error": e}
    return _R(top, gitdir, common, main), None


def _relocate(r: _R, wt: str, expect: Any) -> dict[str, Any] | None:
    """Error dict unless `wt` still locates to the same checkout as `r` (it must not have been redirected while we worked)."""
    again, err = _locate(wt, expect)
    if again is None:
        return err
    if (again.gitdir, again.common) != (r.gitdir, r.common):
        return {"exit_code": 1, "error": f"{wt} was redirected to {again.gitdir} while the call ran"}
    return None


def _packed(r: _R) -> dict[str, str]:
    """{ref name: sha} of <common>/packed-refs, every line validated (peeled `^` lines skipped); a malformed line raises."""
    data = _read_file(os.path.join(r.common, "packed-refs"), 256 << 20)
    out: dict[str, str] = {}
    prev = None
    for n, line in enumerate((data or b"").split(b"\n"), 1):
        if not line or (n == 1 and line.startswith(b"# pack-refs with:")):
            continue
        if prev and re.fullmatch(rb"\^[0-9a-f]{40}", line):  # the peeled value of the tag on the previous line
            prev = None
            continue
        m = re.fullmatch(rb"([0-9a-f]{40}) (\S+)", line)
        name = os.fsdecode(m[2]) if m else ""
        if not m or not _ref_ok(name) or name in out:
            raise ValueError(f"packed-refs line {n} is not `<40-hex sha> <ref>` (sha256 is not supported): {line[:100]!r}")
        out[name] = prev = m[1].decode()
    return out


def _ref_value(r: _R, data: bytes, what: str, hops: int) -> str | None:
    if re.fullmatch(rb"[0-9a-f]{40}\n?", data):
        return data[:40].decode()
    if (m := re.fullmatch(rb"ref: (\S+)\n?", data)):
        if hops >= _SYMREF_HOPS:
            raise ValueError(f"symbolic ref chain longer than {_SYMREF_HOPS} at {what}")
        return _ref(r, os.fsdecode(m[1]), hops + 1)
    if re.fullmatch(rb"[0-9a-f]{64}\n?", data):
        raise ValueError(f"{what}: sha256 object ids are not supported")
    raise ValueError(f"{what}: neither a 40-hex object id nor a symbolic ref: {data[:100]!r}")


def _ref(r: _R, name: str, hops: int = 0) -> str | None:
    """The sha of branch ref `name` (refs/heads/...), read by Python: the loose file under the common dir, else packed-refs;
    None if it does not exist. Symbolic refs are followed (refs/heads/ only, at most _SYMREF_HOPS)."""
    if not (_ref_ok(name) and name.startswith("refs/heads/")):
        raise ValueError(f"unsupported ref name {name!r} (refs/heads/<valid name> only)")
    data = _read_file(os.path.join(r.common, *name.split("/")), 4096)
    return _packed(r).get(name) if data is None else _ref_value(r, data, name, hops)


def _head(r: _R) -> tuple[str, str]:
    """(HEAD's sha, its branch without refs/heads/ or "" when detached), read by Python from <gitdir>/HEAD."""
    data = _read_file(os.path.join(r.gitdir, "HEAD"), 4096)
    if data is None:
        raise ValueError(f"{r.gitdir} has no HEAD")
    m = re.fullmatch(rb"ref: (\S+)\n?", data)
    branch = os.fsdecode(m[1]) if m else ""
    sha = _ref_value(r, data, "HEAD", 0)
    if sha is None:
        raise ValueError(f"HEAD of {r.top} names {branch}, which does not exist (unborn branch)")
    return sha, branch.removeprefix("refs/heads/")


def _refs_named(r: _R, name: str) -> list[str]:
    """Every ref git's DWIM rules would find for `name` (`git rev-parse <name>` resolves a ref before an object id prefix)."""
    rules = (name, f"refs/{name}", f"refs/tags/{name}", f"refs/heads/{name}", f"refs/remotes/{name}", f"refs/remotes/{name}/HEAD")
    packed = _packed(r)
    return [x for x in rules if x in packed or any(os.path.lexists(os.path.join(d, *x.split("/"))) for d in (r.gitdir, r.common))]


def _shadow(r: _R) -> None:
    """The private bare repository under r.tmp: HEAD, an empty refs/, the adapter's own config, info/exclude copied from the real
    repository (ignore patterns are data); no hooks, no info/attributes. Plus the empty `home`."""
    for d in ("objects", "refs", "info"):
        os.makedirs(os.path.join(r.sh, d))
    os.mkdir(os.path.join(r.tmp, "home"))
    for name, data in (("HEAD", b"ref: refs/heads/shadow\n"), ("config", _SHADOW_CONFIG.encode()),
                       ("info/exclude", _read_file(os.path.join(r.common, "info", "exclude")) or b"")):
        with open(os.path.join(r.sh, name), "wb") as f:
            f.write(data)


def _senv(r: _R, index: str | None = None, work: bool = False) -> dict[str, str]:
    """The environment of every git call of the primitives (structure note above): the shadow repository over the real objects;
    `index` = a private GIT_INDEX_FILE (default: the checkout's real index), `work` = GIT_WORK_TREE is the checkout."""
    home = os.path.join(r.tmp, "home")
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_") or k.startswith(_KEEP_GIT_ENV)}
    env |= _NO_DISTORT_ENV | {"GIT_DIR": r.sh, "GIT_OBJECT_DIRECTORY": os.path.join(r.common, "objects"),
                              "GIT_INDEX_FILE": index or os.path.join(r.gitdir, "index"), "HOME": home, "XDG_CONFIG_HOME": home,
                              "GIT_CONFIG_COUNT": str(len(_NO_DISTORT_CONFIG)), "PYTHONSAFEPATH": "1"}
    for i, (k, v) in enumerate(_NO_DISTORT_CONFIG):
        env[f"GIT_CONFIG_KEY_{i}"], env[f"GIT_CONFIG_VALUE_{i}"] = k, v
    env["PATH"] = _abs_path()  # anything git looks up on PATH: never relative to its cwd
    return env | ({"GIT_WORK_TREE": r.top} if work else {})


def _abs_path() -> str:
    """PATH without its empty, `.` and other relative entries (each names the current directory of whoever looks it up)."""
    return os.pathsep.join(d for d in os.environ.get("PATH", os.defpath).split(os.pathsep) if os.path.isabs(d))


def _git_exe() -> str:
    """The git binary every command of the primitives execs: `shutil.which` over the ABSOLUTE PATH entries only, resolved once per
    process (the first call) and used by its absolute path from then on, so no `git` file in a working tree can be picked."""
    if not _GIT_EXE:
        exe = shutil.which("git", path=_abs_path())
        if exe is None:
            raise RuntimeError(f"no git executable on the absolute PATH entries ({_abs_path()!r})")
        _GIT_EXE.append(exe)
    return _GIT_EXE[0]


def _git_where(r: _R) -> str:
    """"" or why the git binary must not be run for checkout `r`: its real path lies in the checkout, the main checkout or the temp
    dir (where a maker or another process can write files)."""
    exe = os.path.realpath(_git_exe())
    for d in (r.top, r.main, tempfile.gettempdir()):
        d = os.path.realpath(d)
        if exe.startswith(d.rstrip("/") + "/"):
            return f"the git binary {exe} lies under {d} (a checkout or the temp dir): refusing to run it"
    return ""


def _git_version(r: _R) -> tuple[int, int]:
    """The git binary's (major, minor), read once per process (`git version`, run like every other command: in the shadow)."""
    if not _GIT_VERSION:
        p = subprocess.run([_git_exe(), "version"], cwd=r.tmp, env=_senv(r), capture_output=True, text=True, check=False)
        m = re.match(r"git version (\d+)\.(\d+)", p.stdout)
        if not m:
            raise RuntimeError(f"cannot read the git version: {(p.stdout + p.stderr).strip()!r}")
        _GIT_VERSION.append((int(m[1]), int(m[2])))
    return _GIT_VERSION[0]


@contextlib.contextmanager
def _open(wt: Any, expect: Any):
    """`with _open(wt, expect) as (r, err)`: the located checkout with its shadow repository (removed afterwards), or (None, error)."""
    r, err = _locate(wt, expect)
    if r is None:
        yield None, err
        return
    r.tmp = tempfile.mkdtemp(prefix="swarm-adapter-")
    try:
        _shadow(r)
        if (e := _git_where(r)):
            yield None, {"exit_code": 1, "error": e}
        elif (v := _git_version(r)) < _MIN_GIT:
            yield None, {"exit_code": 1, "error": f"git >= {_MIN_GIT[0]}.{_MIN_GIT[1]} is required (GIT_NO_LAZY_FETCH), "
                         f"found {v[0]}.{v[1]}"}
        else:
            yield r, None
    finally:
        shutil.rmtree(r.tmp)


def _argv(args: tuple[str, ...]) -> list[str]:
    if args[0] == "diff-tree":  # a gitlink must never be hidden: `.gitmodules` `ignore = all` is read from the TREE too
        args = (args[0], "--ignore-submodules=none", *args[1:])
    return [_git_exe(), *args]


# cwd is always r.tmp, also with `work`: GIT_WORK_TREE alone selects the working tree (measured, git 2.54: `check-ignore --no-index`
# `./<path>` and `read-tree -m -u` from outside it act on it as from its top level).
def _pgit(r: _R, *args: str, index: str | None = None, work: bool = False) -> dict[str, Any]:
    """One git command in the shadow (text result like _git); `index` = a private GIT_INDEX_FILE, `work` = with the working tree."""
    return _sync_run(_argv(args), cwd=r.tmp, env=_senv(r, index, work))


def _git_b(r: _R, *args: str, stdin: bytes | None = None, index: str | None = None, work: bool = False,
           extra: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    """Bytes-in/bytes-out git call in the shadow (same environment as _pgit, plus `extra`)."""
    return subprocess.run(_argv(args), input=stdin, capture_output=True, cwd=r.tmp,
                          env=_senv(r, index, work) | (extra or {}), check=False)


def _err(p: subprocess.CompletedProcess, cmd: str) -> str:
    return os.fsdecode(p.stderr).strip() or f"git {cmd} exited {p.returncode}"


def _git_z(r: _R, *args: str) -> tuple[list[str] | None, str]:
    """NUL-separated git output as fs-decoded str (surrogateescape, so any byte path round-trips into a later argv).
    (None, stderr) when git fails: a failure must never read as "no paths"."""
    p = _git_b(r, *args)
    if p.returncode != 0:
        return None, _err(p, args[0])
    return [os.fsdecode(x) for x in p.stdout.split(b"\0") if x], ""


def _commit_ok(r: _R, sha: str) -> bool:
    """`sha` is a commit object in the store (a missing one is not fetched: GIT_NO_LAZY_FETCH)."""
    p = _pgit(r, "rev-parse", "--verify", "--quiet", "--end-of-options", f"{sha}^{{commit}}")
    return p["exit_code"] == 0 and p["stdout"].strip() == sha


def _scan(top: str) -> tuple[dict[str, str] | None, str]:
    """The working tree, listed by Python (no git): {repo-relative path: git mode} of every regular file (100755 if the owner x bit
    is set, else 100644) and symlink (120000). Symlinks are never followed (what lies beyond one is absent, as for git); the
    top-level `.git` is skipped; other file types (FIFO, socket, device) are skipped, as git does (it cannot store them).
    Error: any `.git` entry (dir, gitfile or symlink) below the top level, i.e. a nested repository or submodule checkout: a git
    command reading the working tree would run commands configured by THAT repository (its filters, via `git status`)."""
    out: dict[str, str] = {}
    nested, todo = [], [""]
    while todo:
        rel = todo.pop()
        with os.scandir(top + "/" + rel if rel else top) as it:
            ents = list(it)
        if rel and any(e.name == ".git" for e in ents):
            nested.append(rel)
            continue
        for e in ents:
            p = rel + "/" + e.name if rel else e.name
            mode = e.stat(follow_symlinks=False).st_mode
            if p == ".git":
                continue
            if stat.S_ISDIR(mode):
                todo.append(p)
            elif stat.S_ISLNK(mode):
                out[p] = "120000"
            elif stat.S_ISREG(mode):
                out[p] = "100755" if mode & stat.S_IXUSR else "100644"
    if nested:
        return None, f"nested git repository / submodule checkout in the working tree (refused before git reads it): {sorted(nested)!r}"
    return out, ""


def _blob(top: str, p: str, mode: str) -> bytes:
    """What git stores for working-tree path `p` of `mode` (as `_scan` saw it): a symlink's target, a regular file's raw bytes.
    The file is opened with O_NOFOLLOW|O_NONBLOCK and must still be a regular file (a swapped-in symlink/FIFO raises)."""
    full = top + "/" + p
    if mode == "120000":
        return os.fsencode(os.readlink(full))
    with open(os.open(full, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            raise OSError(f"{p!r} is no longer a regular file")
        return f.read()


def _oid(data: bytes) -> str:
    """The blob id git gives `data` (sha1 repositories: `_repo_format` refuses any other)."""
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


_MAX_OBJECTS = 1_000_000  # objects one call re-hashes (`_cat`), more is an error
_MAX_OBJECT_BYTES = 4 << 30  # object bytes one call re-hashes (`_cat`), more is an error
_CAT_HEAD = re.compile(rb"([0-9a-f]{40}) (blob|tree|commit|tag) ([0-9]{1,15})\n")
_TREE_ENT = re.compile(rb"([0-7]{5,6}) [^\0/]+\0")


def _cat(r: _R, want: dict[str, str], keep: bool) -> dict[str, bytes]:
    """Read every object of `want` ({oid: the type it must have}) with ONE `cat-file --batch` in the shadow and re-hash it. That is
    git's own object lookup (loose objects, packs and alternates alike), so what is hashed is what git reads for that id. The
    content must hash to the oid as `<type> <size>\\0<content>`; a missing object, another type or another hash raises. Returns
    {oid: content} for trees and commits, and for blobs when `keep` (else a blob is hashed in 1 MiB chunks and dropped: b"").
    The request goes in through a file and the reply is read as it comes, so no pipe can fill up and block. At most _MAX_OBJECTS
    objects and _MAX_OBJECT_BYTES bytes per call (`r.spent`): more raises before the content is read."""
    if not want:
        return {}
    oids = sorted(want)
    r.spent[0] += len(oids)
    if r.spent[0] > _MAX_OBJECTS:
        raise RuntimeError(f"more than {_MAX_OBJECTS} objects to re-hash in one call")
    req = os.path.join(r.tmp, "cat-file.in")
    with open(req, "wb") as f:
        f.write("".join(o + "\n" for o in oids).encode())
    got: dict[str, bytes] = {}
    with open(req, "rb") as fin, tempfile.TemporaryFile(dir=r.tmp) as ferr:
        p = subprocess.Popen(_argv(("cat-file", "--batch")), stdin=fin, stdout=subprocess.PIPE, stderr=ferr, cwd=r.tmp,
                             env=_senv(r))
        try:
            for oid in oids:
                line = p.stdout.readline(128)
                m = _CAT_HEAD.fullmatch(line)
                if not m or m[1].decode() != oid:
                    raise RuntimeError(f"object {oid} cannot be read from the object store: {line[:100]!r}")
                typ, size = m[2].decode(), int(m[3])
                if typ != want[oid]:
                    raise RuntimeError(f"object store forged or corrupt: {oid} is a {typ}, not the {want[oid]} it is named as")
                r.spent[1] += size
                if r.spent[1] > _MAX_OBJECT_BYTES:
                    raise RuntimeError(f"more than {_MAX_OBJECT_BYTES} object bytes to re-hash in one call")
                h, chunks, left = hashlib.sha1(b"%s %d\0" % (m[2], size)), [], size
                while left:
                    b = p.stdout.read(min(left, 1 << 20))
                    if not b:
                        raise RuntimeError(f"git cat-file --batch output ended inside object {oid}")
                    h.update(b)
                    left -= len(b)
                    if keep or typ != "blob":
                        chunks.append(b)
                if p.stdout.read(1) != b"\n":
                    raise RuntimeError(f"git cat-file --batch output malformed after object {oid}")
                if h.hexdigest() != oid:
                    raise RuntimeError(f"object store forged: the {typ} git reads for {oid} hashes to {h.hexdigest()} (a loose "
                                       "object, pack or alternates entry serves other content under this id; `git fsck` names it)")
                got[oid] = b"".join(chunks)
            if p.stdout.read(1) or p.wait() != 0:
                ferr.seek(0)
                raise RuntimeError(f"git cat-file --batch failed: {os.fsdecode(ferr.read(4096)).strip() or 'unexpected output'}")
        finally:
            p.stdout.close()
            if p.poll() is None:
                p.kill()
            p.wait()
    return got


def _subtrees(oid: str, data: bytes) -> list[str]:
    """The ids of the subtree entries (mode 40000) of tree `oid` with content `data`, parsed by Python; a malformed tree raises."""
    out, i = [], 0
    while i < len(data):
        m = _TREE_ENT.match(data, i)
        if not m or m.end() + 20 > len(data):
            raise RuntimeError(f"tree {oid} is malformed at byte {i}")
        if m[1] in (b"40000", b"040000"):
            out.append(data[m.end():m.end() + 20].hex())
        i = m.end() + 20
    return out


def _verify_objects(r: _R, commits: Any = (), trees: Any = (), blobs: Any = ()) -> str:
    """"" or why the object store cannot be trusted for these objects (T6c a17): each commit of `commits` (and the tree its first
    line names), every tree reachable from those and from `trees`, and each blob of `blobs` is re-hashed by `_cat`. Trees are
    walked by Python from their re-hashed content (one `cat-file --batch` per tree depth level), never from a git listing, so a
    forged subtree cannot hide the entries below it. Gitlink entries name commits of another repository and are not followed;
    blobs inside the trees are not read (an oid comparison never reads them; see `_vet_diff` for the blobs a check does read).
    An object re-hashed earlier in the same call is not read again (`r.verified`)."""
    level = {o: "commit" for o in commits} | {o: "tree" for o in trees} | {o: "blob" for o in blobs}
    try:
        while level:
            if (bad := [o for o, t in level.items() if r.verified.get(o, t) != t]):
                raise RuntimeError(f"object store forged or corrupt: {bad[0]} is named as a {level[bad[0]]} and a "
                                   f"{r.verified[bad[0]]}")
            todo = {o: t for o, t in level.items() if o not in r.verified}
            got = _cat(r, todo, keep=False)
            r.verified |= todo
            level = {}
            for o, t in todo.items():
                if t == "commit":
                    if not (m := re.match(rb"tree ([0-9a-f]{40})\n", got[o])):
                        raise RuntimeError(f"commit {o} does not start with a tree line")
                    level[m[1].decode()] = "tree"
                elif t == "tree":
                    level |= dict.fromkeys(_subtrees(o, got[o]), "tree")
    except RuntimeError as e:
        return str(e)
    return ""


def _tree_map(r: _R, treeish: str) -> tuple[dict[str, tuple[str, str]] | None, str]:
    """{path: (mode, oid)} of `ls-tree -r --full-tree <treeish>` (None on git failure)."""
    ent, e = _git_z(r, "ls-tree", "-r", "-z", "--full-tree", treeish)
    if ent is None:
        return None, e
    out = {}
    for x in ent:
        meta, _, p = x.partition("\t")
        mode, _, oid = meta.split(" ")
        out[p] = (mode, oid)
    return out, ""


def _index_map(r: _R) -> tuple[dict[str, tuple[str, str]] | None, str]:
    """{path: (mode, oid)} of the checkout's real index (`ls-files -s -t` in the shadow, GIT_INDEX_FILE=<gitdir>/index); an unmerged
    path is ("unmerged", ""). A skip-worktree entry (sparse checkout) is an error: it is absent from the working tree on purpose and
    would be staged as a deletion. A split index is read and written as usual (measured: plain git reads it afterwards)."""
    ent, e = _git_z(r, "ls-files", "-s", "-t", "-z")
    if ent is None:
        return None, e
    out = {}
    for x in ent:
        meta, _, p = x.partition("\t")
        tag, mode, oid, stage_no = meta.split(" ")
        if tag == "S":
            return None, f"skip-worktree (sparse checkout) entry {p!r} is not supported"
        out[p] = (mode, oid) if stage_no == "0" else ("unmerged", "")
    return out, ""


@dataclass
class _Snap:
    """base / HEAD trees and the index ({path: (mode, oid)}) plus the working tree (`_scan`), blob ids computed on demand;
    `commit` = the HEAD commit (read by Python) the trees were taken from, `branch` its branch ("" when detached)."""
    top: str
    base: dict[str, tuple[str, str]]
    head: dict[str, tuple[str, str]]
    index: dict[str, tuple[str, str]]
    work: dict[str, str]
    oids: dict[str, str]
    commit: str = ""
    branch: str = ""

    def wt(self, p: str) -> tuple[str, str]:
        if p not in self.oids:
            self.oids[p] = _oid(_blob(self.top, p, self.work[p]))
        return self.work[p], self.oids[p]


def _snapshot(r: _R, sha: str, work: dict[str, str]) -> tuple[_Snap | None, str]:
    commit, branch = _head(r)
    if not _commit_ok(r, commit):
        return None, f"HEAD {commit} of {r.top} is not a commit in the object store"
    if (e := _verify_objects(r, commits=(sha, commit))):  # before any listing below reads their trees
        return None, e
    base, e = _tree_map(r, sha)
    if base is None:
        return None, f"git ls-tree {sha} failed: {e}"
    head, e = _tree_map(r, commit)
    if head is None:
        return None, f"git ls-tree HEAD ({commit}) failed: {e}"
    index, e = _index_map(r)
    if index is None:
        return None, f"index: {e}"
    return _Snap(r.top, base, head, index, work, {}, commit, branch), ""


def _st(old: tuple[str, str] | None, new: tuple[str, str] | None) -> str | None:
    """diff status letter of one path (None = unchanged). T = file / symlink / gitlink type change (100644 <-> 100755 is M)."""
    if old == new:
        return None
    if old is None or new is None:
        return "A" if old is None else "D"
    if "unmerged" in (old[0], new[0]):
        return "U"
    return "M" if old[0][:3] == new[0][:3] else "T"


def _kind(s: _Snap, p: str, st: dict[str, str]) -> str:
    if "T" in st.values():
        return "typechange"
    if p in s.work:
        return "symlink" if s.work[p] == "120000" else "file"
    return "gitlink" if s.index.get(p, ("",))[0] == "160000" else "deleted"


def _resolve_base(r: _R, base: str) -> tuple[str | None, dict[str, Any] | None]:
    """(full commit sha, None) or (None, error). The shadow has no refs, so git resolves `base` as an object id prefix only; a ref
    that git's DWIM order would pick in the REAL repository (`git branch <base> HEAD`, a tag, a $GIT_DIR file of that name) is still
    an error (a caller's plain git would resolve the name differently). The resolved sha must start with `base`; a second commit
    with the same prefix makes git itself refuse (ambiguous)."""
    if not (isinstance(base, str) and _HEX.fullmatch(base)):
        return None, {"exit_code": 2, "error": f"base must be a 7-40 digit lowercase hex commit id: {base!r}"}
    sha = _pgit(r, "rev-parse", "--verify", "--quiet", "--end-of-options", f"{base}^{{commit}}")
    full = sha["stdout"].strip()
    if sha["exit_code"] != 0:
        return None, {"exit_code": sha["exit_code"] or 1, "error": f"base {base!r} is not a commit in {r.top}"}
    if (refs := _refs_named(r, base)):
        return None, {"exit_code": 2, "error": f"base {base!r} is ambiguous with a ref name ({refs[0]}): pass the full commit sha"}
    if not (len(full) == 40 and full.startswith(base)):
        return None, {"exit_code": 2, "error": f"base {base!r} resolved to {full!r}, which does not start with it"}
    return full, None


def _change_set(wt: str, base: str, expect: Any) -> dict[str, Any]:
    with _open(wt, expect) as (r, err):
        if r is None:
            return err
        work, e = _scan(r.top)  # before any git command reads objects or the index
        if work is None:
            return {"exit_code": 1, "error": e}
        sha, err = _resolve_base(r, base)
        if sha is None:
            return err
        s, e = _snapshot(r, sha, work)
        if s is None:
            return {"exit_code": 1, "error": e}
        return _change_set_of(r, s, sha)


def _change_set_of(r: _R, s: _Snap, sha: str) -> dict[str, Any]:
    view = {p: s.wt(p) for p in s.work if p in s.index}  # git's working-tree side of `diff <base>`: only paths the index has
    status: dict[str, dict[str, str]] = {}
    for tag, new in (("committed", s.head), ("index", s.index), ("worktree", view)):
        for p in s.base.keys() | new.keys():
            if (st := _st(s.base.get(p), new.get(p))):
                status.setdefault(p, {})[tag] = st
    for p in s.work.keys() - s.index.keys():
        status.setdefault(p, {})["untracked"] = "?"
    n = _pgit(r, "rev-list", "--count", f"{sha}..{s.commit}")
    if n["exit_code"] != 0:
        return {"exit_code": 1, "error": f"git rev-list failed: {n['stderr'].strip()}"}
    return {"paths": {p: {"in": list(st), "kind": _kind(s, p, st)} for p, st in sorted(status.items())},
            "commits": int(n["stdout"]), "branch": s.branch, "exit_code": 0}


@_boundary()
async def change_set(wt: str, base: str, *, expect_common_dir: str | None = None) -> dict[str, Any]:
    """Every path changed since `base` in worktree `wt` (its top level), whatever state the change is in.

    `expect_common_dir` (REQUIRED, absolute; worktree_alloc's `common_dir`) pins the repository: `wt` must belong to that
    git common dir with its own admin dir and a non-symlink `.git`, else {exit_code != 0, error} (a maker can repoint
    `<wt>/.git` at a decoy clone, which would otherwise report an empty change set).

    Returns {paths: {<repo-relative>: {in: [committed|index|worktree|untracked...],
    kind: file|symlink|gitlink|deleted|typechange}}, commits: <commits in base..HEAD>,
    branch: <HEAD's branch without refs/heads/, "" when detached>, exit_code: 0}. committed = base vs HEAD's tree, index = base vs
    the index, worktree = base vs the working-tree content of the paths the index has (as `git diff <base>`), untracked = every file /
    symlink of the working tree the index lacks, IGNORED ONES INCLUDED (they are Tier B checked like any other change; only
    stage_task leaves them out of the commit). Per-path comparison, so a rename is its old and new path. kind: file / symlink = what
    the working tree holds now; gitlink = a gitlink index entry (mode 160000) with nothing in the working tree at that path
    (stage_task refuses it); deleted = nothing there; typechange = file/symlink/gitlink type changed in any column.
    No git command runs in the repository (structure note above `_EMPTY_TREE`): Python locates it, reads HEAD and lists the working
    tree (symlinks not followed) and hashes its blobs raw (no filters: a repository relying on eol/`filter=` attributes shows those
    paths as changed); git, in the private shadow repository, only reads trees (`ls-tree`) and the index (`ls-files -s`). A nested
    repository or submodule checkout (a `.git` entry below the top level) is an `error`; so is a skip-worktree (sparse checkout) index
    entry, a missing object (never fetched), and a sha256 / reftable / shallow repository; so is a forged object store: base's and
    HEAD's commit and every tree they reach are re-hashed before anything is listed (`_verify_objects`, T6c a17).
    `base` must be 7-40 lowercase hex, must not also be a ref name, and must resolve to a commit whose full sha starts with
    it; only that full sha is used afterwards. Replace refs and grafts are ignored (GIT_NO_REPLACE_OBJECTS, GIT_GRAFT_FILE).
    Any failure (missing worktree, unknown base, unreadable file, ...) is {exit_code != 0, error} with no `paths` (fail-closed).
    """
    return await _a(_change_set, wt, base, expect_common_dir)


def _write_scope_rules() -> tuple[dict[str, Any] | None, str | None, str]:
    """agent/write-scope-rules.json next to this module ONLY (no ~/.prime fallback): (rules, path, error)."""
    agent = _repo_agent_dir()
    path = agent / "write-scope-rules.json" if agent else None
    if path is None or not path.is_file():
        return None, str(path) if path else None, f"write-scope-rules.json not found ({path})"
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as e:
        return None, str(path), f"{path} unreadable: {type(e).__name__}: {e}"
    # stricter than decide.py's write_scope check: an empty list can never be a legitimate Tier B rule set
    if not (isinstance(data, dict) and all(isinstance(data.get(k), list) and data[k]
                                           and all(isinstance(x, str) for x in data[k]) for k in _WS_KEYS)):
        return None, str(path), f"{path} malformed: needs non-empty string lists {_WS_KEYS}"
    return data, str(path), ""


def _tier_b_match(rules: dict[str, Any], path: str, home: str) -> bool:
    """write_scope_is_protected() of write-scope-lib.sh: case-sensitive fnmatch, ${HOME} expanded (parity-tested)."""
    return (any(fnmatch.fnmatchcase(path, p) for p in rules["suffix_patterns"])
            or any(fnmatch.fnmatchcase(path, p.replace("${HOME}", home)) for p in rules["fixed_absolute_path_patterns"]))


def _tier_b_hits(wt: str, paths: list[str], expect: Any) -> dict[str, Any]:
    if isinstance(paths, (str, bytes, os.PathLike)):  # one path, not a list: iterating it would split it per character
        raise TypeError("paths must be a list of repo-relative str paths, not a single path")
    paths = list(dict.fromkeys(paths))
    if not all(isinstance(p, str) for p in paths):
        raise TypeError("paths must be repo-relative str paths")
    rules, rpath, err = _write_scope_rules()
    if rules is None:
        return {"hits": paths, "rules": rpath, "exit_code": 1, "error": err}  # unknown rules: every path protected
    r, terr = _locate(wt, expect)  # Python only: no git command at all
    if r is None:
        return {"hits": paths, "rules": rpath, **terr}
    home = os.path.expanduser("~")
    devs = _special_devs()
    hits = []
    for p in paths:
        # As written in the tree (git stores a symlink as a blob: the unresolved path is what a commit carries),
        # resolved (edit-time view), and the main checkout's twin (prime worktrees live outside the fixed patterns).
        # An absolute `p` (the resolved target of a symlink that points outside the repository) is matched as it is.
        # Resolved by `_real`, never os.path.realpath: a candidate through /proc/self/cwd, /dev/fd ... or a special mount
        # raises (T6c a16: realpath answered for THIS process's cwd, and an untracked `ig/s -> /proc/self/cwd/.claude` passed).
        cands = {p} if os.path.isabs(p) else {b + "/" + p for b in (os.path.abspath(wt), r.top, r.main)}
        cands |= {_real(c, devs) for c in cands}
        if any(_tier_b_match(rules, c, home) for c in cands):
            hits.append(p)
    return {"hits": hits, "rules": rpath, "exit_code": 0}


def _given_paths(items: list[Any]) -> list[str]:
    """Every given path that can be read as one (str, bytes, PathLike; fs-decoded): the fail-closed `hits`. Never raises."""
    out = []
    for p in items:
        try:
            out.append(os.fsdecode(p))
        except TypeError:  # not path-like: cannot be named in hits; exit_code != 0 still refuses the call
            continue
    return list(dict.fromkeys(out))


@_boundary()
async def tier_b_hits(wt: str, paths: list[str], *, expect_common_dir: str | None = None) -> dict[str, Any]:
    """Which repo-relative `paths` of worktree `wt` (its top level) are Tier B (agent/write-scope-rules.json).

    Returns {hits: [paths], rules: <abs rules path>, exit_code: 0}. A path hits if ANY candidate matches:
    <wt>/P unresolved, its realpath, <main checkout>/P unresolved (main = parent of the git common dir), its realpath.
    Each realpath is `_real` (the disk, element by element): one that touches /proc, /dev, /sys or a special mount is an error
    (T6c a16). The rules file is looked up only next to this module. `paths` is materialised once (a generator/map/filter
    works); a bare str/bytes/PathLike is an error (it would be split per character). `expect_common_dir` (REQUIRED, absolute) pins the
    repository as in change_set (located by Python; no git command runs). ANY failure (missing/unreadable/malformed rules, a bad or
    non-str `wt`, a NUL byte, a non-str path, a wrong repository, ...) gives exit_code != 0, `error`, and hits = every given path that
    is path-like (fail-closed). Callers MUST treat exit_code != 0 as "refuse", never read `hits` alone.
    """
    if isinstance(paths, (str, bytes, os.PathLike)):
        return {"hits": _given_paths([paths]), "rules": None, "exit_code": 2,
                "error": "paths must be a list of repo-relative paths, not a single str (it would be split per character)"}
    try:
        items = list(paths)  # the ONLY consumption of `paths`: a one-shot iterable must reach both the hits fallback and the check
    except Exception as e:
        return {"hits": [], "rules": None, "exit_code": 1, "error": f"{type(e).__name__}: {e}"}
    given = _given_paths(items)
    try:
        return await _a(_tier_b_hits, wt, items, expect_common_dir)
    except Exception as e:  # not swallowed: converted to the fail-closed error shape WITH hits (the boundary has no paths)
        return {"hits": given, "rules": None, "exit_code": 1, "error": f"{type(e).__name__}: {e}"}


def _ignored(r: _R, paths: list[str]) -> tuple[set[str] | None, str]:
    """The subset of `paths` that the ignore rules exclude (None on git failure): `check-ignore --no-index --stdin -z` in the shadow
    with the working tree, which reads the .gitignore files and the shadow's info/exclude (a copy of the real one) and runs nothing.
    The global core.excludesFile is NOT applied (no global config is read). Each path is sent as `./<path>` so that a name such as
    `:/x` or `:(glob)*` is not read as pathspec magic (check-ignore rejects `--literal-pathspecs`)."""
    if not paths:
        return set(), ""
    r_ = _git_b(r, "check-ignore", "--no-index", "--stdin", "-z", stdin=b"".join(b"./" + os.fsencode(p) + b"\0" for p in paths),
                work=True)
    if r_.returncode not in (0, 1):  # 1 = none ignored
        return None, _err(r_, "check-ignore")
    return {os.fsdecode(x[2:]) for x in r_.stdout.split(b"\0") if x}, ""


def _write_blobs(r: _R, blobs: dict[str, tuple[str, str]]) -> str:
    """Write the objects of `blobs` ({path: (mode, oid)}) into the repository's object store; "" or an error message. Each
    working-tree content is read again (it must still hash to `oid`) into a private copy under r.tmp, and `hash-object -w
    --no-filters --stdin-paths` reads those copies: git never opens a working-tree path, and what it stores is what was checked."""
    names, oids = [], []
    for i, (p, (mode, oid)) in enumerate(sorted(blobs.items())):
        data = _blob(r.top, p, mode)
        if _oid(data) != oid:
            return f"{p!r} changed while it was being staged"
        names.append(os.path.join(r.tmp, f"blob{i}"))
        with open(names[-1], "wb") as f:
            f.write(data)
        oids.append(oid)
    if not names:
        return ""
    if "\n" in r.tmp:
        return f"temporary directory {r.tmp!r} contains a newline (hash-object --stdin-paths is line-based)"
    p = _git_b(r, "hash-object", "-w", "--no-filters", "--stdin-paths", stdin=b"".join(os.fsencode(n) + b"\n" for n in names))
    if p.returncode != 0 or p.stdout.decode(errors="replace").split() != oids:
        return f"git hash-object failed: {_err(p, 'hash-object') if p.returncode else 'unexpected object ids'}"
    return ""


_MAX_HOPS = 40  # symlinks followed per link (Linux MAXSYMLINKS), more is an error
_MAX_LINKS = 1000  # symlinks of one tree `_vet_diff` resolves, more is an error
_MAX_TOTAL_HOPS = 100_000  # symlinks followed by one `_vet_diff` over every link and location, more is an error
# Paths the kernel resolves per ACCESSING process (/proc/self, /proc/thread-self, /proc/<pid>/{cwd,root,fd}, /dev/fd, /dev/stdin,
# ...) or that are no repository content at all: a walk reaching one is an error (T6c a15). The whole of /dev and /sys, not just
# the magic names, so that a container whose /dev is a tmpfs is covered the same as a host with devtmpfs.
_SPECIAL_PREFIXES = ("/proc", "/dev", "/sys")
_SPECIAL_FS = frozenset({"proc", "sysfs", "devtmpfs", "devpts", "cgroup", "cgroup2", "mqueue", "debugfs", "tracefs", "securityfs",
                         "pstore", "bpf", "configfs", "fusectl", "binfmt_misc", "efivarfs", "selinuxfs", "nsfs"})


def _special_path(p: str) -> bool:
    """`p` (absolute) STARTS at or below one of _SPECIAL_PREFIXES: empty and `.` elements dropped first (`//proc`, `/./proc` count),
    `..` kept as written (`/proc/self/cwd/../..` still starts in /proc)."""
    p = "/" + "/".join(c for c in p.split("/") if c not in ("", "."))
    return any(p == x or p.startswith(x + "/") for x in _SPECIAL_PREFIXES)


def _special_devs() -> frozenset[int]:
    """st_dev of every mount whose file system type is in _SPECIAL_FS (a proc / sysfs / devpts ... mounted at ANY path, e.g. a
    bind mount of /proc elsewhere), from /proc/self/mountinfo read by Python (`major:minor` is the st_dev lstat reports for every
    entry of that mount). Raises if it cannot be read or parsed: no answer is no check (fail-closed)."""
    data = _read_file("/proc/self/mountinfo", 1 << 24)
    if not data:
        raise RuntimeError("cannot read /proc/self/mountinfo (needed to refuse links into process-dependent file systems)")
    devs = set()
    for line in data.splitlines():
        head, sep, tail = line.partition(b" - ")
        fields, fs = head.split(), tail.split()
        if not sep or len(fields) < 5 or not fs or fields[2].count(b":") != 1:
            raise RuntimeError(f"unexpected /proc/self/mountinfo line: {line!r}")
        if fs[0].decode(errors="replace") in _SPECIAL_FS:
            major, minor = fields[2].split(b":")
            devs.add(os.makedev(int(major), int(minor)))
    return frozenset(devs)


def _disk(at: str, link: str, devs: frozenset[int]) -> tuple[int | None, str | None]:
    """The disk's answer for element `at` (absolute; every element above it already resolved, so lstat follows no symlink of the
    walk) of a walk resolving `link`: (st_mode, symlink target or None); (None, None) if nothing is there (ENOENT/ENOTDIR).
    Raises when `at` is at or below a _SPECIAL_PREFIXES path or on a _SPECIAL_FS mount (`devs`), and on any other
    lstat/readlink error."""
    if _special_path(at):
        raise RuntimeError(f"symlink {link!r} resolves through {at!r}: a process-dependent / special file system path")
    try:
        st = os.lstat(at)
    except (FileNotFoundError, NotADirectoryError):  # nothing there (yet)
        return None, None
    if st.st_dev in devs:
        raise RuntimeError(f"symlink {link!r} resolves through {at!r}: on a special file system mount (proc, sysfs, ...)")
    return st.st_mode, os.readlink(at) if stat.S_ISLNK(st.st_mode) else None


def _real(path: str, devs: frozenset[int]) -> str:
    """os.path.realpath(`path`) (absolute) by the disk alone, element by element as the kernel does (`..` applies to the element
    already resolved; a missing element is kept as named), WITHOUT its blind spot: realpath answers /proc/self/cwd, /dev/fd ... for
    THIS process, so a path through them is an error here (`_disk`; a symlink target at or below a _SPECIAL_PREFIXES path too, T6c
    a16). More than _MAX_HOPS symlinks raise. Used wherever a path is resolved on disk: tier_b_hits' candidates, the twin
    re-walk's start, the checkout locations."""
    if not path.startswith("/"):
        raise ValueError(f"not an absolute path: {path!r}")
    done, todo, hops = [""], path.split("/")[:0:-1], 0
    while todo:
        c = todo.pop()
        if c in ("", "."):
            continue
        if c == "..":
            if len(done) > 1:
                done.pop()
            continue
        done.append(c)
        target = _disk("/".join(done), path, devs)[1]
        if target is None:
            continue
        if target.startswith("/") and _special_path(target):
            raise RuntimeError(f"{path!r} resolves through a link to {target!r}: a special file system path")
        hops += 1
        if hops > _MAX_HOPS:
            raise RuntimeError(f"symlink chain too deep: {path!r}")
        done.pop()
        if target.startswith("/"):
            done = [""]
        todo += target.split("/")[::-1]
    return "/".join(done) or "/"


def _raw(r: _R, cmd: str, *args: str) -> tuple[list[tuple[str, str, str, str, str]] | None, str]:
    """[(old mode, new mode, old oid, new oid, path)] of `git <diff|diff-tree> --raw -z --no-renames <args>` (None on git
    failure)."""
    out, err = _git_z(r, cmd, "--no-renames", "--raw", "-z", *(("-r",) if cmd == "diff-tree" else ()), *args)
    if out is None or len(out) % 2:
        return None, err or f"unexpected {cmd} --raw output"
    ents = []
    for meta, path in zip(out[0::2], out[1::2]):  # ":<old mode> <new mode> <old oid> <new oid> <status>", <path>
        m = meta.lstrip(":").split(" ")
        ents.append((m[0], m[1], m[2], m[3], path))
    return ents, ""


def _link_final(top: str, links: dict[str, str], read, link: str, locs: list[str] | tuple[str, ...], devs: frozenset[int],
                budget: list[int], tree: dict[str, str], forks: list[tuple[str, str]], ondisk: str = "") -> str:
    """Where symlink `link` (repo-relative) points with the tree checked out at `top`, resolved element by element in the
    kernel's order (each element is resolved before the next one, `..` included, is applied to it). An element INSIDE `top` that
    the TREE has is resolved by the tree (`tree`: every path of the tree -> its mode, every directory -> "040000"; `links`: every
    symlink of the tree, path -> blob oid; `read` returns a blob's text; a non-symlink is a plain entry). An element inside `top`
    that the tree does NOT have (untracked, ignored, or a name the tree lacks: a checkout leaves it on disk, T6c a16) and an
    element OUTSIDE `top` are resolved by the DISK (`_disk`: lstat; a symlink is read and followed, so `<outside symlink>/..` is
    the parent of its target, T6c a14).
    TREE AND DISK DISAGREEING INSIDE `top` (T6c a16): every element inside `top` is lstat'ed too. Where the disk holds an entry
    other than the tree's (a symlink where the tree has none or another target; a directory or file where the tree has a symlink;
    a directory where the tree has a file), BOTH are checked: the walk goes on with the tree, and (the absolute path from that
    element on, the elements not yet applied appended as written; the element, repo-relative) is appended to `forks` for the
    caller to walk again with `ondisk` = that element: in such a walk the element and everything below it count as absent from
    the tree (the disk decides); the rest is resolved as above (another location entered is still resolved with the tree there,
    a further disagreement forks again). A checkout does not always replace what the disk holds (`read-tree -m -u` / `merge
    --ff-only` keep a local change at a path the merge leaves alone; another worktree never gets this tree), so neither view
    alone is the truth; an error instead would refuse every retargeted symlink (the main checkout's disk still holds the old
    target). Below an element whose disk entry is a symlink or whose tree entry is not a directory, nothing more is read from
    disk in the tree's walk (an lstat there would follow the disk's symlink in THIS process's view; the fork covers the disk).
    Every fork is taken from `budget` too. Hops of both kinds count against _MAX_HOPS (more raises, so does an lstat/readlink
    error other than a missing element). Exceptions to "by the disk": the directories above `top` are taken as named (`top` is
    a location as given,
    its realpath is a location of its own); an element that does not exist (ENOENT/ENOTDIR: the kernel has no answer yet, one may
    be created) is kept as a plain name and the walk goes on (safe side); and once the path enters another location of `locs` the
    walk stops: the absolute path, the elements not yet applied appended as written, for the caller to resolve again from there
    with the tree (the twin, `_vet_diff`). Returns the absolute path, repo-relative when it is inside `top`. An absolute `link` is
    resolved the same way from `/`.
    PROCESS-DEPENDENT FILE SYSTEMS ARE AN ERROR (T6c a15): the kernel resolves /proc/self, /proc/thread-self, /proc/<pid>/cwd|root,
    /dev/fd, /dev/stdin ... for the process that LOOKS, so what this process reads there says nothing about the process that later
    opens the link (`x -> /proc/self/cwd/../dotfiles/.claude/settings.json` is main's settings.json for a process whose cwd is
    the main checkout, wherever the adapter runs). Raises when (a) an element the walk lstats (outside every location, or inside
    `top` whether the tree has it or not, T6c a16) is at or below a
    _SPECIAL_PREFIXES path, (b) its lstat st_dev is a mount of a _SPECIAL_FS type (`devs`: a proc/sysfs/... mounted elsewhere), or
    (c) a symlink target (tree or disk) is an absolute path at or below a _SPECIAL_PREFIXES path. Every hop is also taken from the
    caller's shared `budget` ([remaining hops]; below 0 raises)."""
    base = top.split("/")
    others = [o.split("/") for o in locs if o != top]
    hidden: set[str] = set()  # in-top paths below which the disk is not this checkout's (see the docstring)
    done, todo, hops = [""], (link if link.startswith("/") else top + "/" + link).split("/")[:0:-1], 0
    while todo:
        c = todo.pop()
        if c in ("", "."):
            continue
        if c == "..":
            if len(done) > 1:
                done.pop()
        else:
            done.append(c)
        target = None
        if done[:len(base)] == base:  # inside top: the tree; the disk where the tree has nothing (and both where they disagree)
            rel = "/".join(done[len(base):])
            kind = tree.get(rel) if c != ".." and rel and not (ondisk and (rel + "/").startswith(ondisk + "/")) else None
            if kind == "120000":
                target = read(links[rel])
            if c != ".." and rel and not any(rel.startswith(h + "/") for h in hidden):
                mode, disk = _disk("/".join(done), link, devs)  # the special path / mount checks for every element of the checkout
                if kind is None:  # untracked / ignored / not in this tree: what the disk holds stays there after a checkout
                    target = disk
                else:
                    if mode is not None and (disk != target or (kind != "040000" and stat.S_ISDIR(mode))):
                        budget[0] -= 1
                        if budget[0] < 0:
                            raise RuntimeError(f"symlink resolution budget exceeded: more than {_MAX_TOTAL_HOPS} hops over every "
                                               "link and location")
                        forks.append(("/".join(done + todo[::-1]), rel))
                    if disk is not None or kind != "040000":
                        hidden.add(rel)
        elif base[:len(done)] == done:  # a directory above top: as named
            continue
        elif any(done[:len(o)] == o for o in others):  # another checkout of the tree: resolved again from there
            return "/".join(done + todo[::-1])
        elif c != "..":  # outside every location: the disk (`..` pops an element that is already resolved)
            target = _disk("/".join(done), link, devs)[1]
        if target is not None:
            if target.startswith("/") and _special_path(target):
                raise RuntimeError(f"symlink {link!r} resolves through a link to {target!r}: a special file system path")
            hops += 1
            budget[0] -= 1
            if hops > _MAX_HOPS:
                raise RuntimeError(f"symlink chain too deep: {link!r}")
            if budget[0] < 0:
                raise RuntimeError(f"symlink resolution budget exceeded: more than {_MAX_TOTAL_HOPS} hops over every link and location")
            done.pop()
            if target.startswith("/"):
                done = [""]
            todo += target.split("/")[::-1]
    out = "/".join(done)
    return out[len(top) + 1:] if out.startswith(top + "/") else out


_SLOT = "swarm-prime-any-worktree"  # stands for any `<slug>-<ts>` worktree_alloc may create under a worktree root


def _locations(r: _R, devs: frozenset[int] | None = None) -> list[str]:
    """Every top level at which the tree being vetted may be checked out (T6c a13), as given and as realpath: this checkout
    (r.top), the main checkout (r.main), every linked worktree registered in `<common>/worktrees/*/gitdir` (read by Python; this
    includes the mission and task worktrees), and one stand-in `<root>/_SLOT` per worktree_alloc root (`<main parent>/.worktrees/
    <main name>`, and $SWARM_WORKTREE_DIR as worktree_alloc would use it now) for worktrees not created yet. The realpath is
    `_real` (a location through /proc, /dev, /sys or a special mount raises).
    A REGISTRATION IS VERIFIED BEFORE IT IS USED (T6c a16: the shared git dir is writable by a maker, and a forged
    `<common>/worktrees/<n>/gitdir` made any directory a "checkout of the tree"). Each entry of `<common>/worktrees` must be a
    real directory; one without `gitdir` registers nothing (git prunes it) and is skipped. Otherwise the admin dir must hold
    `HEAD` and a `commondir` naming THIS common dir (git writes both before the checkout, and keeps them when the checkout is
    deleted by hand), and `gitdir` must name `<wt>/.git` with `<wt>` neither a symlink nor a special path. If that `.git` does
    not exist the worktree is git's "prunable" one (deleted by hand): nothing is checked out there, and it stays a location
    (the a13 behaviour). Else `<wt>` must locate (`_locate`) to THIS admin dir (`.git` a gitfile naming it, `gitdir` naming that
    `.git` back). Anything else RAISES: a forged or broken registration stops the check (so does one caught in the middle of a
    concurrent `git worktree add`: retry). A registration forged consistently in every file IS a worktree to git and is kept;
    that is safe: being a location only ADDS views (the tree there, on top of the disk: the disk is still read where the tree
    has nothing or disagrees, and tier_b_hits resolves every absolute path on disk with `_real`)."""
    devs = _special_devs() if devs is None else devs
    tops = {r.top, r.main}
    adm = os.path.join(r.common, "worktrees")
    if os.path.isdir(adm):
        with os.scandir(adm) as it:
            ents = list(it)
        for e in ents:
            if not e.is_dir(follow_symlinks=False):
                raise RuntimeError(f"{e.path} is not a directory: not a worktree registration git makes (forged or broken)")
            data = _read_file(os.path.join(e.path, "gitdir"), 4096)
            if data is None:  # an admin dir without `gitdir` belongs to no checkout
                continue
            cd, head = _read_file(os.path.join(e.path, "commondir"), 4096), _read_file(os.path.join(e.path, "HEAD"), 4096)
            if cd is None or head is None or _real(os.path.join(e.path, os.fsdecode(cd.rstrip(b"\r\n"))), devs) != r.common:
                raise RuntimeError(f"worktree registration {e.path} lacks HEAD or a commondir naming {r.common} (forged or broken)")
            dotgit = os.path.normpath(os.path.join(e.path, os.fsdecode(data.rstrip(b"\r\n"))))
            wt = os.path.dirname(dotgit)
            if os.path.basename(dotgit) != ".git" or _special_path(wt) or os.path.islink(wt):
                raise RuntimeError(f"{e.path}/gitdir names {dotgit!r}: not the .git of a real worktree directory (forged or broken)")
            if not os.path.lexists(dotgit):  # prunable: nothing checked out there (see above)
                tops.add(wt)
                continue
            got, err = _locate(wt, r.common)
            if got is None or got.gitdir != os.path.realpath(e.path):
                why = err["error"] if got is None else f"its .git names {got.gitdir}"
                raise RuntimeError(f"worktree registration {e.path} -> {wt} does not check out: {why} (forged or broken)")
            tops.add(wt)
    main = Path(r.main)
    roots = {str(main.parent / ".worktrees" / main.name)}
    if (root := _worktree_base(main, Path(r.top))[0]) is not None:  # None: inside the repo, worktree_alloc refuses it
        roots.add(str(root))
    tops |= {os.path.join(x, _SLOT) for x in roots}
    return sorted({os.path.abspath(t) for t in tops} | {_real(os.path.abspath(t), devs) for t in tops})


def _vet_diff(r: _R, ents: list[tuple[str, str, str, str, str]], treeish: str) -> tuple[list[str], str]:
    """(extra paths to Tier B check, error) for the diff entries `ents` (`_raw`) that lead to `treeish`. Error: any gitlink (mode
    160000) added, changed or removed; a blob on either side of an entry, or a symlink blob of `treeish`, that does not re-hash
    to its id (`_cat`, T6c a17: the trees themselves are re-hashed by the caller before its diff). Extra: when the diff adds, changes or removes ANY symlink (mode 120000 on either side,
    which includes a directory replaced by a symlink and back), the final target of EVERY symlink of `treeish`, resolved INSIDE
    `treeish` (a path in the repository when it points inside, an absolute one when it points outside; a link that dangles
    in the tree keeps the path it names): the Tier B check reads the working tree, which the index need not match. Every link,
    not just the added ones (T6c a15): an unchanged `y -> d/write-scope-rules.json` names agent/write-scope-rules.json once a
    task turns the directory `d` into `d -> agent`. Inside the tree only symlinks steer a walk, so a diff that touches none
    leaves every link where it was (nothing is resolved then). Cost caps, each an error when exceeded: _MAX_LINKS symlinks in
    the tree, _MAX_TOTAL_HOPS hops over every link, location and twin re-walk. A walk that touches a process-dependent / special
    file system (/proc, /dev, /sys, or a proc/sysfs/... mount anywhere: `_link_final`) raises.
    WHERE A LINK POINTS DEPENDS ON WHERE THE TREE IS CHECKED OUT: `x -> ../dotfiles/.claude/settings.json` leaves a prime
    worktree (two levels deeper than the main checkout) for a harmless path, but names the main checkout's own settings.json once
    the tree reaches the main checkout (T6c a12 Checker). So each link is resolved with the tree at every `_locations(r)` entry
    (`_link_final`: inside the location by the tree, outside every location by the disk, element by element in the kernel's
    order, T6c a14); a path that enters another location, and a final absolute path whose realpath lies inside one, is resolved
    again from there (the twin: that checkout holds the tree too) and so reported repo-relative, which tier_b_hits checks against
    <wt>/<main checkout>. Every result is returned (repo-relative or absolute; a stopped walk's path as written, `..` included).
    Inside a location an element the tree lacks is read from disk, and where the disk disagrees with the tree both views are
    walked (`_link_final` forks: walked again with that element taken from disk, T6c a16). Every disk resolution here and in
    tier_b_hits is `_real`, which raises on a special file system where os.path.realpath answered for this process;
    `_locations` verifies each worktree registration (a forged one raises).
    Residual risk: a checkout of the tree at a top level NOT in `_locations` (a worktree made by hand elsewhere, a clone, a
    different $SWARM_WORKTREE_DIR or a name a link spells out for a worktree not created yet) can still resolve a relative link
    differently; a directory symlink to a Tier B directory is only a hit through a path that names a Tier B file below it (a path
    in the diff or a symlink of the tree); the disk outside the repository is read now: a symlink created or changed there later
    (also at an element missing now) can move where an already-checked link points, and a diff that touches no symlink is not
    re-walked even if the disk changed; the same holds for the disk INSIDE the locations (an untracked/ignored symlink, a local
    change, a registration added later); tree and disk are combined per walk only as "the tree" or "from one disagreeing
    element on, the disk" (forks), not every mix; a loop or special path in any view is an error (more walks, more refusals); a
    FUSE or other file system not in _SPECIAL_FS that answers per process is not recognized."""
    if (gl := sorted(p for o, n, _, _, p in ents if "160000" in (o, n))):
        return [], f"gitlink / submodule entries are not allowed in a task result: {gl!r}"
    if (e := _verify_objects(r, blobs={x for o, n, a, b, _ in ents for m, x in ((o, a), (n, b)) if m != "000000"})):
        return [], e
    if not any("120000" in (o, n) for o, n, *_ in ents):  # no symlink added, changed or removed: every link resolves as before
        return [], ""
    tm, e = _tree_map(r, treeish)
    if tm is None:
        return [], f"git ls-tree {treeish} failed: {e}"
    links = {q: oid for q, (mode, oid) in tm.items() if mode == "120000"}
    if len(links) > _MAX_LINKS:
        return [], f"too many symlinks to resolve in {treeish}: {len(links)} > {_MAX_LINKS}"

    try:  # every link's target text, re-hashed (one `cat-file --batch`): a forged symlink blob must not steer the walk
        got = _cat(r, dict.fromkeys(links.values(), "blob"), keep=True)
    except RuntimeError as x:
        return [], str(x)
    texts = {oid: os.fsdecode(data) for oid, data in got.items()}  # the SAME representation as the `links` keys (0xff -> U+DCFF)
    read = texts.__getitem__

    devs = _special_devs()
    locs, budget = _locations(r, devs), [_MAX_TOTAL_HOPS]
    # every path of the tree -> its mode, every directory above one -> "040000" (`ls-tree -r` lists no directories)
    tree = {q[:i]: "040000" for q in tm for i in range(len(q)) if q[i] == "/"} | {q: mode for q, (mode, _) in tm.items()}
    out: set[str] = set()
    todo = [(loc, p, 0, "") for loc in locs for p in links]
    seen: set[tuple[str, str, str]] = set()
    while todo:
        loc, p, depth, ondisk = todo.pop()
        if (loc, p, ondisk) in seen:
            continue
        seen.add((loc, p, ondisk))
        forks: list[tuple[str, str]] = []
        f = _link_final(loc, links, read, p, locs, devs, budget, tree, forks, ondisk)
        out.add(f)
        if (forks or f.startswith("/")) and depth >= _MAX_HOPS:
            raise RuntimeError(f"symlink chain too deep across checkouts: {p!r}")
        todo += [(loc, g, depth + 1, e) for g, e in forks]  # the disk's view where it disagrees with the tree (`_link_final`)
        if f.startswith("/"):  # it left `loc`: where it lands may be another location's checkout of the same tree
            for a in {f, _real(f, devs)}:
                todo += [(other, a, depth + 1, "") for other in locs if a.startswith(other + "/")]
    return sorted(out), ""


def _stage_task(wt: str, base: str, exclude: Any, expect: Any) -> dict[str, Any]:
    excl = {exclude} if isinstance(exclude, str) else set(exclude)
    with _open(wt, expect) as (r, err):
        if r is None:
            return err
        work, e = _scan(r.top)  # before any git command reads objects or the index
        if work is None:
            return {"exit_code": 1, "error": e}
        sha, err = _resolve_base(r, base)
        if sha is None:
            return err
        s, e = _snapshot(r, sha, work)
        if s is None:
            return {"exit_code": 1, "error": e}
        # base must be an ancestor of HEAD (a maker's `git reset --hard base~1` / `git checkout <other>` is not a task result): the
        # tree built below is diffed against base, and a HEAD behind base would make that diff the REVERSE of base's own commits.
        if _pgit(r, "merge-base", "--is-ancestor", sha, s.commit)["exit_code"] != 0:  # 1 = not an ancestor; other = git failure
            return {"exit_code": 1, "error": f"base {sha} is not an ancestor of HEAD of {wt}: HEAD was moved behind or away from it"}
        cs = _change_set_of(r, s, sha)
        if cs["exit_code"] != 0:
            return cs
        head = s.head
        # The commit = the working tree, minus `exclude` (kept at HEAD's entry, or absent) and minus IGNORED files that neither HEAD
        # nor the index has (never committed before: `git add` would skip them too; a path HEAD has stays subject to the working tree,
        # so `git rm --cached` + keeping the file stages it as a change). Ignored files are still in the Tier B check below.
        ignored, e = _ignored(r, sorted(p for p in work if p not in s.index and p not in head))
        if ignored is None:
            return {"exit_code": 1, "error": f"git check-ignore failed: {e}"}
        want = {p: s.wt(p) for p in work if p not in ignored and p not in excl} | {p: head[p] for p in excl if p in head}
        moved = {p for p in work.keys() | head.keys() if p not in work or p not in head or s.wt(p) != head[p]}  # HEAD vs working tree
        seen = set(cs["paths"]) | moved | {p for p in s.index.keys() | head.keys() if s.index.get(p) != head.get(p)}
        tb = _tier_b_hits(wt, sorted(seen), expect)  # excluded and ignored paths are checked too
        if tb["exit_code"] != 0:
            return {"tier_b": tb["hits"], "exit_code": tb["exit_code"], "error": tb["error"]}
        if tb["hits"]:
            return {"staged": [], "tier_b": tb["hits"], "zero_diff": False, "exit_code": _TIER_B_REFUSED}
        # the working tree never holds a gitlink (`_scan` refuses a checkout of one), so one in HEAD/the index would be staged as its removal
        if (links := sorted({p for m in (head, s.index) for p, (mode, _) in m.items() if mode == "160000"})):
            return {"exit_code": 1, "error": f"gitlink absent from the working tree cannot be staged (gitlink entry in HEAD or the index): {links!r}"}
        return _stage_tree(r, wt, sha, s, want, seen, excl, expect)


def _stage_tree(r: _R, wt: str, sha: str, s: _Snap, want: dict[str, tuple[str, str]], seen: set[str], excl: set[str],
                expect: Any) -> dict[str, Any]:
    """Build `want` in a private index under r.tmp, verify the tree, then put it in the real index."""
    index = os.path.join(r.tmp, "index")
    known = {oid for m in (s.base, s.head, s.index) for _, oid in m.values()}
    if (e := _write_blobs(r, {p: v for p, v in want.items() if v[1] not in known})):
        return {"exit_code": 1, "error": e}
    info = b"".join(b"%s %s\t%s\0" % (m.encode(), o.encode(), os.fsencode(p)) for p, (m, o) in sorted(want.items()))
    p = _git_b(r, "update-index", "-z", "--index-info", stdin=info, index=index)
    if p.returncode != 0:
        return {"exit_code": 1, "error": f"update-index --index-info (private index) failed: {_err(p, 'update-index')}"}
    # THE invariant: the tree this function returns is checked, not the inputs it was derived from. Anything that wrote the private
    # index after `want` was computed is in this tree.
    tree = _pgit(r, "write-tree", index=index)
    if tree["exit_code"] != 0:
        return {"exit_code": tree["exit_code"], "error": f"git write-tree failed: {tree['stderr'].strip()}"}
    tree = tree["stdout"].strip()
    if (e := _verify_objects(r, trees=(tree,))):  # write-tree reuses a subtree whose id is already in the store, whatever it holds
        return {"exit_code": 1, "error": e}
    ents, e = _raw(r, "diff-tree", sha, tree)  # base -> what would be committed
    if ents is None:
        return {"exit_code": 1, "error": f"git diff-tree {sha} {tree} failed: {e}"}
    extra, e = _vet_diff(r, ents, tree)  # no gitlink; symlink targets resolved in the tree itself
    if e:
        return {"exit_code": 1, "error": e}
    tb = _tier_b_hits(wt, sorted(seen | {p for *_, p in ents} | set(extra)), expect)
    if tb["exit_code"] != 0:
        return {"tier_b": tb["hits"], "exit_code": tb["exit_code"], "error": tb["error"]}
    if tb["hits"]:  # the real index was not touched
        return {"staged": [], "tier_b": tb["hits"], "zero_diff": False, "exit_code": _TIER_B_REFUSED}
    got, e = _tree_map(r, tree)
    if got is None:
        return {"exit_code": 1, "error": f"git ls-tree {tree} failed: {e}"}
    if (miss := sorted(p for p, v in want.items() if got.get(p) != v)):  # every intended entry is in the tree exactly as staged
        return {"exit_code": 1, "error": f"index does not match the working tree after staging: not staged {miss!r}"}
    staged, e = _git_z(r, "diff-tree", "-r", "--no-renames", "--name-only", "-z", s.commit, tree)  # from the verified tree
    if staged is None:
        return {"exit_code": 1, "error": f"git diff-tree HEAD {tree} failed: {e}"}
    if excl.intersection(staged):
        return {"exit_code": 1, "error": f"excluded but staged: {sorted(excl.intersection(staged))!r}"}
    if (bad := _relocate(r, wt, expect)):  # the repository must not have been redirected while we worked (nor before the index write)
        return bad
    p = _pgit(r, "read-tree", tree)  # the REAL index (GIT_INDEX_FILE=<gitdir>/index): only now, only the verified tree (no -m/-u)
    again = _pgit(r, "write-tree") if p["exit_code"] == 0 else p
    if again["exit_code"] != 0 or again["stdout"].strip() != tree:
        return {"exit_code": 1, "error": f"index changed while the staged tree {tree} was being verified: "
                f"{again['stdout'].strip() or again['stderr'].strip()}"}
    base_tree = _pgit(r, "rev-parse", "--verify", "--quiet", "--end-of-options", f"{sha}^{{tree}}")
    if base_tree["exit_code"] != 0:
        return {"exit_code": 1, "error": f"git rev-parse {sha}^{{tree}} failed: {base_tree['stderr'].strip()}"}
    # zero_diff is a statement about the tree handed out: it is base's own tree, so committing it changes nothing relative to base.
    return {"staged": staged, "tier_b": [], "zero_diff": tree == base_tree["stdout"].strip(), "tree": tree, "head": s.commit,
            "exit_code": 0}


@_boundary()
async def stage_task(wt: str, base: str, exclude: tuple[str, ...] | list[str] | str = ("@fix_plan.md",),
                     *, expect_common_dir: str | None = None) -> dict[str, Any]:
    """Stage a finished task's worktree for the caller's commit, after the Tier B check. Never commits.

    `expect_common_dir` (REQUIRED, absolute; worktree_alloc's `common_dir`) pins the repository as in change_set.
    What is staged: the working tree as change_set reads it (Python; raw bytes, no filters), minus `exclude` (exact
    repo-root-relative names: kept at HEAD's entry, or left out if HEAD lacks it, whatever the maker staged) and minus ignored files
    that neither HEAD nor the index has (`check-ignore`: .gitignore files + the repository's info/exclude; never committed, as
    `git add` would skip them). So the commit == the working tree for every other path: a deletion/rename the maker already committed
    or left unstaged, `git rm --cached` + keeping the file (staged as a change), an index-only change (resynced to the working tree).
    Check first: change_set(wt, base) paths | HEAD vs working tree | HEAD vs index, IGNORED AND EXCLUDED PATHS INCLUDED, go
    through tier_b_hits. Tier B hits: {staged: [], tier_b: [hits], zero_diff: False, exit_code: 3}, nothing staged. A nested
    repository / submodule checkout in the working tree, a skip-worktree index entry, and any gitlink (mode 160000) in HEAD or
    the index (the working tree cannot hold one, so it would be staged as its removal) are an `error`.
    Build: the result is assembled in a PRIVATE index (a mkdtemp GIT_INDEX_FILE): new blobs written by `hash-object -w
    --no-filters` from private copies, `update-index --index-info`, `write-tree`. Then the RESULT is verified (every object read
    re-hashed first, T6c a17: base's and HEAD's commit and trees, the result's trees, both blobs of each diff entry, every symlink
    blob; a mismatch is an `error`): `diff-tree
    base..tree` (what a commit of that tree adds) is Tier B checked together with every earlier path and with the final target of
    every symlink of the tree once that diff adds, changes or removes any symlink (mode 120000, read from the tree and followed
    inside it, so an index-injected symlink blob counts; a process-dependent / special file system on the way is an error;
    an absolute path when it points outside the repository; resolved with the tree at every checkout location, since a relative
    link's target depends on where it is checked out: `_vet_diff`); a gitlink added, changed or removed in that diff is an error
    (`--ignore-submodules=none`); every intended entry must be in the tree as intended; no excluded path may differ from HEAD in it.
    Only then is the REAL index written, with `read-tree <tree>` (no -m/-u), and it must write back the same tree. Every failure
    before that leaves the real index as it was.
    Returns {staged: <HEAD vs the verified tree>, tier_b: [], zero_diff: <`tree` is base's own tree>, tree, head: <the HEAD commit
    it was staged on>, exit_code: 0}. `base` must be an ancestor of HEAD (else `error`, before anything is staged): a maker's
    `git reset --hard base~1` leaves a HEAD behind base, and the tree built from it differs from base's by the REVERSE of base's own
    commits. zero_diff is decided on the tree: commits the maker made and then undid (tree == base's tree) are zero_diff True.
    No git command runs in the repository (structure note above `_EMPTY_TREE`; GIT_TRACE2_EVENT: 0 child_start events).
    Commit ONLY with commit_tree(wt, tree, [head], msg) + update_ref(wt, commit, head) (SKILL.md "Commit and merge"): the commit is
    exactly `tree` on top of `head`, and the branch moves only if it still is `head`. Never `git commit`: after `read-tree` the index
    has no stat data, so a working-tree command re-hashes every file through the filters the shared config names.
    Callers MUST treat exit_code != 0 as "refuse, commit nothing": every failure is {exit_code != 0, error}
    (tier_b = every path if the rules are unusable; no `tier_b` when the inputs/worktree are unusable).
    """
    return await _a(_stage_task, wt, base, exclude, expect_common_dir)


def _incoming(mission_wt: str, branch: str, expect: Any) -> dict[str, Any]:
    if not isinstance(branch, str) or branch in ("", "HEAD", "@") or not _ref_ok(f"refs/heads/{branch}"):
        return {"exit_code": 2, "error": f"branch must name a local branch (refs/heads/<branch>), got {branch!r}"}
    with _open(mission_wt, expect) as (r, err):
        if r is None:
            return err
        ref = f"refs/heads/{branch}"
        sha = _ref(r, ref)  # exact ref only (Python): no DWIM to a tag / sha / HEAD
        if sha is None or not _commit_ok(r, sha):
            return {"exit_code": 1, "error": f"{ref} is not a local branch with a commit in {mission_wt} ({sha})"}
        head, _ = _head(r)
        if not _commit_ok(r, head):
            return {"exit_code": 1, "error": f"HEAD {head} of {mission_wt} is not a commit in the object store"}
        if (e := _verify_objects(r, commits=(head, sha))):
            return {"exit_code": 1, "error": f"{ref}: {e}"}
        # The merge RESULT, not a two-dot/three-dot diff: with several merge bases (criss-cross history) `git diff head...sha` uses
        # just the first one while ort builds a virtual base, so the diff can miss a path the merge changes (measured). merge-tree
        # runs that ort merge (no working tree, no ref moved), in the shadow: no merge driver / filter can be selected; the result
        # tree is written to the object store, and it is what the caller commits (commit_tree), so the merge cannot differ from it.
        mt, e = _git_z(r, "merge-tree", "--write-tree", "-z", "--no-messages", head, sha)
        if mt is None or len(mt) != 1 or not _SHA.fullmatch(mt[0]):
            return {"exit_code": 1, "error": f"git merge-tree {head} {sha} ({ref}) failed or conflicts, do not merge: {e or mt}"}
        tree = mt[0]
        if (e := _verify_objects(r, trees=(tree,))):
            return {"exit_code": 1, "error": f"{ref}: {e}"}
        ents, e = _raw(r, "diff-tree", head, tree)  # what the merge changes in the mission
        if ents is None:
            return {"exit_code": 1, "error": f"git diff-tree {head} {tree} ({ref}) failed: {e}"}
        extra, e = _vet_diff(r, ents, tree)
    if e:
        return {"exit_code": 1, "error": f"{ref}: {e}"}
    return {"paths": sorted({p for *_, p in ents} | set(extra)), "sha": sha, "head": head, "tree": tree, "exit_code": 0}


@_boundary()
async def incoming(mission_wt: str, branch: str, *, expect_common_dir: str | None = None) -> dict[str, Any]:
    """Paths a merge of `branch` would change in `mission_wt` (its top level): `git diff-tree head <result of merge-tree head sha>`.

    `branch` must be an existing local branch (`refs/heads/<branch>`, read by Python); "", "HEAD", "@" (e.g. change_set's "" for a
    detached HEAD), a tag, a sha, an invalid ref name or a '-'-leading name are refused, and the branch's resolved sha is what is
    merged. `expect_common_dir` (REQUIRED, absolute) pins the repository as in change_set.
    Returns {paths, sha: <the branch commit that was checked>, head: <the mission HEAD commit it was checked against>,
    tree: <the tree the merge produces>, exit_code: 0}; `paths` also holds the final target of every symlink of `tree` once the merge
    adds, changes or removes any symlink (resolved
    inside `tree` with the tree at every checkout location of the repository, main checkout included, as in `_vet_diff`; absolute when
    it points outside the repository). The result of the ort merge is checked, not a `head...sha` diff
    (with several merge bases that diff uses only the first one: measured, it hid a Tier B change); a conflict is an error. merge-tree
    runs in the private shadow repository (no config, attributes or hooks of the repository: no merge driver can be selected). Feed
    `paths` to tier_b_hits(mission_wt, paths), then merge exactly this result with the SKILL.md "Commit and merge" steps:
    commit_tree(mission_wt, tree, [head, sha], msg) + update_ref(mission_wt, commit, head, checkout=True), then verify_merge. Never
    `git merge` (it reads the shared config: drivers, filters, hooks, lazy fetch). A gitlink (mode 160000) in the result diff is an
    error (no `paths`). Replace refs and grafts are ignored. `head`'s and `sha`'s commit, every tree they and the result reach,
    both blobs of each diff entry and every symlink blob read are re-hashed (a forged object store is an `error`, T6c a17).
    Any failure is {exit_code != 0, error} with no `paths`; callers MUST treat it as "do not merge".
    """
    if (bad := _bad_dash(branch=branch)):
        return bad
    return await _a(_incoming, mission_wt, branch, expect_common_dir)


def _verify_merge(mission_wt: str, head: str, expect: Any) -> dict[str, Any]:
    if not (isinstance(head, str) and _SHA.fullmatch(head)):
        return {"exit_code": 2, "error": f"head must be the full 40-digit lowercase hex commit id the merge started from: {head!r}"}
    with _open(mission_wt, expect) as (r, err):
        if r is None:
            return err
        cur, _ = _head(r)
        if not (_commit_ok(r, cur) and _commit_ok(r, head)):
            return {"exit_code": 1, "error": f"HEAD {cur} or {head} is not a commit in {mission_wt}"}
        if (e := _verify_objects(r, commits=(head, cur))):
            return {"exit_code": 1, "error": e}
        if _pgit(r, "merge-base", "--is-ancestor", head, cur)["exit_code"] != 0:  # 1 = not an ancestor; other = git failure
            return {"exit_code": 1, "error": f"HEAD {cur} is not a descendant of {head}: the merge was not made on top of it"}
        ents, e = _raw(r, "diff-tree", head, cur)
        if ents is None:
            return {"exit_code": 1, "error": f"git diff-tree {head} {cur} failed: {e}"}
        extra, e = _vet_diff(r, ents, cur)
        if e:
            return {"exit_code": 1, "head": cur, "error": e}
        paths = sorted({p for *_, p in ents} | set(extra))
        tb = _tier_b_hits(mission_wt, paths, expect)
        if tb["exit_code"] != 0:
            return {"tier_b": tb["hits"], "exit_code": tb["exit_code"], "error": tb["error"]}
        if (bad := _relocate(r, mission_wt, expect)):
            return bad
    return {"paths": paths, "tier_b": tb["hits"], "head": cur, "exit_code": _TIER_B_REFUSED if tb["hits"] else 0}


@_boundary()
async def verify_merge(mission_wt: str, head: str, *, expect_common_dir: str | None = None) -> dict[str, Any]:
    """After the merge: check what the merge actually committed. READ-ONLY (it resets nothing).

    `head` = the full 40-hex mission HEAD from before the merge (incoming's `head`). `expect_common_dir` (REQUIRED, absolute)
    pins the repository as in change_set. HEAD (read by Python) must be a descendant of `head`; `diff-tree -r head HEAD` (committed
    trees only, in the shadow) is then checked: any gitlink (mode 160000) entry is an error, and every changed path plus the final
    target of every symlink of HEAD's tree once that diff adds, changes or removes any symlink (resolved inside HEAD's tree, as for
    stage_task) goes through the Tier B check. `head`'s and HEAD's commit, every tree they reach, both blobs of each diff entry and
    every symlink blob read are re-hashed first (a forged object store is an `error`, T6c a17).
    Returns {paths, tier_b: [hits], head: <HEAD that was checked>, exit_code}: 0 = clean, 3 = Tier B hit, other = error (gitlink,
    not a descendant, git failure, ...). Anything but 0 means STOP and report to a human: do not `git reset --hard` (this
    function never destroys anything, and the caller should not either).
    """
    return await _a(_verify_merge, mission_wt, head, expect_common_dir)


def _ident() -> dict[str, str]:
    """GIT_AUTHOR_*/GIT_COMMITTER_* for commit-tree: what the caller's environment lacks is taken from user.name / user.email of the
    user's GLOBAL git config (GIT_CONFIG_GLOBAL, else $XDG_CONFIG_HOME/git/config and ~/.gitconfig; parsed by Python, includes not
    followed). Never from the repository's config, which a maker can write."""
    g = os.environ.get("GIT_CONFIG_GLOBAL")
    files = [g] if g is not None else [os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "git",
                                                    "config"), os.path.expanduser("~/.gitconfig")]
    vals: dict[str, str] = {}
    for f in files:
        if f != os.devnull and (data := _read_file(f, follow=True)) is not None:
            vals |= _config_values(os.fsdecode(data), strict=False)
    return {f"GIT_{role}_{k.upper()}": vals[f"user.{k}"] for role in ("AUTHOR", "COMMITTER") for k in ("name", "email")
            if f"GIT_{role}_{k.upper()}" not in os.environ and f"user.{k}" in vals}


def _parents(r: _R, sha: str) -> list[str] | None:
    """The parents of commit `sha` AS GIT READS THEM (`rev-list --parents -n1`, in the shadow: no grafts, replace refs or commit-graph),
    None if git fails. Never parsed from the object text: git takes only the `parent` lines right after `tree`, so a `parent` line
    after `committer` (which plain `hash-object -t commit -w` writes) is no parent to git (T6c a11 checker)."""
    p = _pgit(r, "rev-list", "--parents", "-n1", sha)
    ids = p["stdout"].split()
    if p["exit_code"] != 0 or not ids or ids[0] != sha or not all(_SHA.fullmatch(x) for x in ids):
        return None
    return ids[1:]


def _commit_tree(wt: str, tree: str, parents: Any, msg: str, expect: Any) -> dict[str, Any]:
    parents = [parents] if isinstance(parents, str) else list(parents)
    if not (isinstance(tree, str) and _SHA.fullmatch(tree)) or not 1 <= len(parents) <= 2 or \
            not all(isinstance(p, str) and _SHA.fullmatch(p) for p in parents):
        return {"exit_code": 2, "error": f"tree and 1-2 parents must be full 40-hex ids: {tree!r} {parents!r}"}
    if not (isinstance(msg, str) and msg.strip() and "\0" not in msg):
        return {"exit_code": 2, "error": "msg must be a non-empty str without NUL"}
    with _open(wt, expect) as (r, err):
        if r is None:
            return err
        if _pgit(r, "cat-file", "-t", tree)["stdout"].strip() != "tree":
            return {"exit_code": 1, "error": f"{tree} is not a tree in the object store"}
        if (bad := [p for p in parents if not _commit_ok(r, p)]):
            return {"exit_code": 1, "error": f"parent(s) {bad!r} are not commits in the object store"}
        if (e := _verify_objects(r, commits=parents, trees=(tree,))):
            return {"exit_code": 1, "error": e}
        p = _git_b(r, "commit-tree", tree, *(x for q in parents for x in ("-p", q)), "-m", msg, extra=_ident())
        commit = p.stdout.decode(errors="replace").strip()
        if p.returncode != 0 or not _SHA.fullmatch(commit):
            return {"exit_code": 1, "error": f"git commit-tree failed: {_err(p, 'commit-tree')} (set GIT_AUTHOR_NAME/EMAIL and "
                    "GIT_COMMITTER_NAME/EMAIL, or user.name/user.email in the global git config)"}
        if (e := _verify_objects(r, commits=(commit,))):  # an object already stored under that id is kept as it is, not rewritten
            return {"exit_code": 1, "error": e}
        if (got := _parents(r, commit)) != parents:  # e.g. a duplicate `-p`, which commit-tree drops with exit 0
            return {"exit_code": 1, "error": f"git reads the parents of the written commit {commit} as {got}, not {parents}"}
    return {"commit": commit, "tree": tree, "parents": parents, "exit_code": 0}


@_boundary()
async def commit_tree(wt: str, tree: str, parents: list[str], msg: str, *, expect_common_dir: str | None = None) -> dict[str, Any]:
    """Write a commit OBJECT for `tree` with `parents` (1 or 2 full shas) and message `msg` into the repository of `wt`: no ref, no
    index and no working tree is touched (update_ref is the step that moves the branch).

    `expect_common_dir` (REQUIRED, absolute) pins the repository as in change_set. Runs `commit-tree` in the private shadow repository
    (no hooks, no signing: commits made here are NOT signed, since gpg.program & co. live in config a maker can write). Author and
    committer: GIT_AUTHOR_*/GIT_COMMITTER_* of the environment, else user.name/user.email of the user's GLOBAL git config (never the
    repository's). The written commit's parents are read back from git (`rev-list --parents`) and must equal `parents` (commit-tree
    drops a duplicate `-p` with exit 0). The parents, `tree` (every tree it reaches) and the written commit are re-hashed: an object
    already stored under the new commit's id is kept as it is by git, so a planted one is an `error` (T6c a17).
    Returns {commit, tree, parents, exit_code: 0} or {exit_code != 0, error}.
    """
    return await _a(_commit_tree, wt, tree, parents, msg, expect_common_dir)


def _cas_branch(r: _R, ref: str, new: str, old: str, before, undo) -> str:
    """Move loose ref `ref` from `old` to `new` the way git's files backend does (`<ref>.lock` created O_EXCL, value re-read and
    compared under the lock, written, renamed over the ref); `before()` runs under the lock right before the rename and may return
    an error. Everything that can be checked or written ahead is done before `before()`: the ref path must be absent or a regular file
    (a directory there made the rename fail after the checkout) and `new` is already written and fsynced into the lock, so only the
    rename follows it; if that fails, `undo()`'s text (it undoes what `before()` did) is appended to the error. Every directory below
    the common dir is opened O_NOFOLLOW (a symlinked refs/heads/... cannot redirect the write).
    "" on success, else the reason (the ref is then unchanged)."""
    parts = ref.split("/")
    dfd = os.open(r.common, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for d in parts[:-1]:
            try:
                os.mkdir(d, dir_fd=dfd)
            except FileExistsError:
                pass
            nfd = os.open(d, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dfd)
            os.close(dfd)
            dfd = nfd
        name, lock = parts[-1], parts[-1] + ".lock"
        try:
            lfd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o666, dir_fd=dfd)
        except FileExistsError:
            return f"{ref}.lock exists: another process is updating {ref}"
        done = False
        try:
            try:
                st = os.lstat(name, dir_fd=dfd)
            except FileNotFoundError:
                st = None
            if st is not None and not stat.S_ISREG(st.st_mode):
                return f"{ref} is not a regular file (a directory or symlink is in its place): it cannot be written (nothing changed)"
            data = _read_file(name, 4096, dir_fd=dfd)
            if data is not None and not re.fullmatch(rb"[0-9a-f]{40}\n?", data):
                return f"{ref} is not a plain 40-hex ref: {data[:100]!r}"
            cur = data[:40].decode() if data is not None else _packed(r).get(ref)
            if cur != old:
                return f"{ref} is {cur}, not {old}: it moved (nothing changed)"
            line = f"{new}\n".encode()
            if os.write(lfd, line) != len(line):
                return f"short write to {ref}.lock (nothing changed)"
            os.fsync(lfd)
            if (e := before()):
                return e
            try:
                os.rename(lock, name, src_dir_fd=dfd, dst_dir_fd=dfd)
            except OSError as x:
                return f"writing {ref} failed ({type(x).__name__}: {x}): it is still {old}" + undo()
            done = True
        finally:
            os.close(lfd)
            if not done:
                os.unlink(lock, dir_fd=dfd)
    finally:
        os.close(dfd)
    return ""


def _update_ref(wt: str, new: str, old: str, checkout: bool, expect: Any) -> dict[str, Any]:
    if not all(isinstance(x, str) and _SHA.fullmatch(x) for x in (new, old)):
        return {"exit_code": 2, "error": f"new and old must be full 40-hex commit ids: {new!r} {old!r}"}
    with _open(wt, expect) as (r, err):
        if r is None:
            return err
        m = re.fullmatch(rb"ref: (refs/heads/swarm-prime/\S+)\n?", _read_file(os.path.join(r.gitdir, "HEAD"), 4096) or b"")
        ref = os.fsdecode(m[1]) if m else ""
        if not _ref_ok(ref):
            return {"exit_code": 1, "error": f"HEAD of {wt} is not on a refs/heads/swarm-prime/* branch (detached, or a branch the "
                    "adapter did not allocate): refusing to move it"}
        if not (_commit_ok(r, old) and _commit_ok(r, new)) or (parents := _parents(r, new)) is None:
            return {"exit_code": 1, "error": f"{old} or {new} is not a commit in the object store"}
        if parents[:1] != [old]:  # git's own reading of `new` (above), never the object text
            return {"exit_code": 1, "error": f"{new}'s first parent (as git reads it) is {parents[:1]}, not {old}: only a fast-forward "
                    "onto a new commit whose first parent is the current tip is allowed"}
        if _pgit(r, "merge-base", "--is-ancestor", old, new)["exit_code"] != 0:  # 1 = not an ancestor; other = git failure
            return {"exit_code": 1, "error": f"{old} is not an ancestor of {new} (git merge-base --is-ancestor): refusing"}
        moved: list[bool] = []  # set once read-tree -m -u has put `new` into the index and working tree

        def undo() -> str:
            """After a failed ref write: the index and working tree back to `old` (git's checks keep a change made meanwhile)."""
            if not moved:
                return ""
            back = _pgit(r, "read-tree", "-m", "-u", new, old, work=True)
            if back["exit_code"] != 0:
                return (f"; the index and working tree hold {new}'s tree and could NOT be restored to {old}'s: "
                        f"{back['stderr'].strip()} (`git status` shows it; restore them by hand)")
            return f"; the index and working tree were restored to {old}'s tree"

        def before() -> str:
            if _read_file(os.path.join(r.gitdir, "HEAD"), 4096) != m[0]:
                return f"HEAD of {wt} changed while the ref was locked"
            if not checkout:
                return ""
            work, e = _scan(r.top)  # a nested repository is refused before read-tree reads the working tree
            if work is None:
                return e
            idx = _pgit(r, "write-tree")
            otree = _pgit(r, "rev-parse", "--verify", "--quiet", "--end-of-options", f"{old}^{{tree}}")
            if idx["exit_code"] != 0 or idx["stdout"].strip() != otree["stdout"].strip():
                return f"the index of {wt} is not {old}'s tree (staged changes): {idx['stderr'].strip() or 'refusing to check out'}"
            co = _pgit(r, "read-tree", "-m", "-u", old, new, work=True)  # git's own "would be overwritten" checks, in the shadow
            if co["exit_code"] != 0:
                return f"read-tree -m -u {old} {new} failed (nothing moved): {co['stderr'].strip()}"
            moved.append(True)
            return ""

        if (e := _cas_branch(r, ref, new, old, before, undo)):
            return {"exit_code": 1, "error": e}
        if _ref(r, ref) != new:
            return {"exit_code": 1, "error": f"{ref} is not {new} after the update"}
    return {"ref": ref, "old": old, "new": new, "exit_code": 0}


@_boundary()
async def update_ref(wt: str, new: str, old: str, *, checkout: bool = False,
                     expect_common_dir: str | None = None) -> dict[str, Any]:
    """Fast-forward the branch checked out in `wt` from `old` to `new` (compare-and-swap); the step that makes a commit_tree commit
    the branch tip. Not destructive by construction: HEAD must be a symbolic ref to a `refs/heads/swarm-prime/*` branch (what
    worktree_alloc creates), `new`'s FIRST parent must be `old` (history is only ever extended by one commit, never rewound or
    replaced; undo = move it back to that parent), and the branch must still be `old` under its lock. The parents are git's own
    reading of `new` (`rev-list --parents -n1`, in the shadow), never parsed from the object text (a `parent` line after `committer`
    is no parent to git), and `old` must be an ancestor of `new` (`merge-base --is-ancestor`); both before the lock is taken.

    `expect_common_dir` (REQUIRED, absolute) pins the repository as in change_set. The ref is written by Python like git's files
    backend (`<ref>.lock` O_EXCL, re-read under the lock, rename; no reflog entry), never by `git update-ref` (which reads the shared
    config: hooks, lazy fetch of a missing object). `checkout=True` (the merge): before the ref moves, under its lock, the real index
    and working tree go from `old`'s tree to `new`'s with `read-tree -m -u old new` in the private shadow (no filters, hooks or
    drivers can be named there; git's own checks refuse to overwrite a local change or an untracked file, and nothing is written
    then); the index must equal `old`'s tree first and the working tree must hold no nested repository. Before that checkout the ref
    path must be absent or a regular file and `new` is already written into the lock, so only the rename follows it; if the rename
    fails, `read-tree -m -u new old` puts the index and working tree back to `old` and the `error` says whether that worked (git
    refuses to overwrite a change made meanwhile: then they stay at `new` and the error says so). Returns {ref, old, new,
    exit_code: 0} or {exit_code != 0, error} (the ref is unchanged on every error; with checkout=True an I/O failure in the middle of
    read-tree can leave the working tree partly updated: `git status` shows it).
    """
    return await _a(_update_ref, wt, new, old, checkout, expect_common_dir)
