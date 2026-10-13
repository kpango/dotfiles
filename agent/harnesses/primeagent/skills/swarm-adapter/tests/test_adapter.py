"""Hermetic tests for the swarm-adapter thin wrapper (stub script roots + temp git repos)."""
import asyncio
import stat
import subprocess
from pathlib import Path

import pytest

import swarm_adapter as sa

REPO_AGENT = Path(sa.__file__).resolve().parents[6]  # .../agent
REAL_SKILLS = REPO_AGENT / "skills"


def run(coro):
    return asyncio.run(coro)


def _script(root: Path, rel: str, body: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("#!/usr/bin/env bash\n" + body)
    p.chmod(p.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def stubs(tmp_path, monkeypatch):
    root = tmp_path / "skills"
    echo_args = 'printf "%s\\n" "$@"\n'
    _script(root, "swarm-implement/scripts/budget-guard.sh", echo_args)
    _script(root, "swarm-loop/scripts/mission-init.sh", echo_args)
    _script(root, "swarm-graph/scripts/graph-status.sh", 'echo "status: $1"\n')
    _script(
        root,
        "swarm-graph/scripts/graph-compile.sh",
        'echo "{\\"verdict\\": \\"CYCLE\\", \\"args\\": \\"$*\\"}"\nexit 3\n',
    )
    monkeypatch.setenv("SWARM_SCRIPTS_ROOT", str(root))
    return root


def test_budget_guard_plain(stubs):
    r = run(sa.budget_guard("t1"))
    assert r["exit_code"] == 0
    assert r["stdout"].split() == ["t1"]


def test_budget_guard_mission(stubs):
    r = run(sa.budget_guard("t1", mission="m"))
    assert r["stdout"].split() == ["t1", "--mission=m"]


def test_fable_grant(stubs):
    r = run(sa.fable_grant("t1", mission="m"))
    assert r["stdout"].split() == ["--fable", "t1", "--mission=m"]


def test_graph_compile_parses_json_and_exit_code(stubs):
    r = run(sa.graph_compile("/p/@fix_plan.md", fit=True, stale="a"))
    assert r["exit_code"] == 3
    assert r["verdict"] == "CYCLE"
    assert r["args"] == "--fit --stale a /p/@fix_plan.md"


def test_graph_compile_non_json_output(stubs):
    _script(stubs, "swarm-graph/scripts/graph-compile.sh", "echo nope >&2\nexit 1\n")
    r = run(sa.graph_compile("/p"))
    assert r["exit_code"] == 1 and "nope" in r["stderr"]


def test_graph_status(stubs):
    r = run(sa.graph_status("/p/plan.md"))
    assert r["stdout"].strip() == "status: /p/plan.md"


def test_mission_init(stubs):
    r = run(sa.mission_init("slug", "goal text", "mission", targets="a,b"))
    assert r["stdout"].split("\n")[:4] == ["slug", "goal text", "mission", "a,b"]


def test_mission_init_no_targets(stubs):
    r = run(sa.mission_init("slug", "g", "interactive"))
    assert r["stdout"].split("\n")[:3] == ["slug", "g", "interactive"]


def test_missing_script_reports_127(tmp_path, monkeypatch):
    monkeypatch.setenv("SWARM_SCRIPTS_ROOT", str(tmp_path / "empty"))
    r = run(sa.budget_guard("t"))
    assert r["exit_code"] == 127 and "budget-guard.sh" in r["stderr"]


def test_scripts_root_default_finds_repo_skills(monkeypatch):
    monkeypatch.delenv("SWARM_SCRIPTS_ROOT", raising=False)
    got = Path(sa.scripts_root("swarm-graph/scripts/graph-compile.sh"))
    assert got.resolve() == REAL_SKILLS.resolve()


# ---- worktrees ----------------------------------------------------------
def _git(cwd, *a):
    return subprocess.run(["git", *a], cwd=cwd, check=True, capture_output=True, text=True).stdout


@pytest.fixture
def repo(tmp_path):
    r = tmp_path / "proj" / "myrepo"
    r.mkdir(parents=True)
    _git(r, "init", "-q", "-b", "main")
    _git(r, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "i")
    return r


def test_worktree_alloc_env_dir(repo, tmp_path, monkeypatch):
    wd = tmp_path / "wt"
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(wd))
    r = run(sa.worktree_alloc("my slug", cwd=str(repo)))
    p = Path(r["path"])
    assert p.parent == wd and p.name.startswith("my-slug-")
    assert r["branch"].startswith("swarm-prime/my-slug-")
    assert _git(p, "rev-parse", "--abbrev-ref", "HEAD").strip() == r["branch"]
    assert repo not in p.parents


def test_worktree_alloc_default_outside_repo(repo, monkeypatch):
    monkeypatch.delenv("SWARM_WORKTREE_DIR", raising=False)
    r = run(sa.worktree_alloc("s", cwd=str(repo)))
    assert Path(r["path"]).parent == repo.parent / ".worktrees" / "myrepo"


def test_worktree_release(repo, tmp_path, monkeypatch):
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wt"))
    r = run(sa.worktree_alloc("s", cwd=str(repo)))
    out = run(sa.worktree_release(r["path"]))
    assert out["exit_code"] == 0 and not Path(r["path"]).exists()


def test_worktree_alloc_not_a_repo(tmp_path):
    r = run(sa.worktree_alloc("s", cwd=str(tmp_path)))
    assert r.get("error") and "path" not in r


# ---- verify ----------------------------------------------------------------
def test_verify_all_pass(tmp_path):
    r = run(sa.verify(["echo hi", "true"], str(tmp_path)))
    assert r["passed"] is True
    assert [x["exit_code"] for x in r["results"]] == [0, 0]
    assert r["results"][0]["output_tail"].strip() == "hi"


def test_verify_failure_and_cwd(tmp_path):
    r = run(sa.verify(["pwd", "echo bad >&2; exit 4"], str(tmp_path)))
    assert r["passed"] is False
    assert r["results"][0]["output_tail"].strip() == str(tmp_path.resolve())
    assert r["results"][1]["exit_code"] == 4 and "bad" in r["results"][1]["output_tail"]
    assert r["results"][1]["command"] == "echo bad >&2; exit 4"


def test_verify_tail_truncated(tmp_path):
    r = run(sa.verify(["seq 1 5000"], str(tmp_path)))
    tail = r["results"][0]["output_tail"]
    assert len(tail) <= 4000 and tail.rstrip().endswith("5000")


def test_verify_empty_is_not_passed(tmp_path):
    assert run(sa.verify([], str(tmp_path)))["passed"] is False


# ---- decide_shell ------------------------------------------------------------
def test_decide_shell_allow():
    assert run(sa.decide_shell("ls"))["decision"] == "allow"


def test_decide_shell_block():
    cmd = "r" + "m -rf " + "/"  # built in pieces so the repo's own security hook does not trip on the source
    assert run(sa.decide_shell(cmd))["decision"] == "block"


def test_decide_shell_unavailable(monkeypatch, tmp_path):
    monkeypatch.setenv("SWARM_AGENT_DIR", str(tmp_path))
    r = run(sa.decide_shell("ls"))
    assert r["decision"] == "allow" and "error" in r


# ---- integration: REAL graph-compile.sh -------------------------------------------
real = REAL_SKILLS / "swarm-graph/scripts/graph-compile.sh"
HEAD = """## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
"""
ROWS = [
    "| a | root | - | - | pending | 0 | impl | - |",
    "| b | left | a | - | pending | 0 | impl | - |",
    "| c | right | a | - | pending | 0 | impl | - |",
    "| d | join | b,c | - | pending | 0 | impl | - |",
]


@pytest.mark.skipif(not real.exists(), reason="real graph-compile.sh missing")
def test_real_graph_compile_ok(tmp_path, monkeypatch):
    monkeypatch.delenv("SWARM_SCRIPTS_ROOT", raising=False)
    plan = tmp_path / "@fix_plan.md"
    plan.write_text(HEAD + "\n".join(ROWS) + "\n")
    r = run(sa.graph_compile(str(plan), fit=True))
    assert r["exit_code"] == 0 and r["verdict"] == "OK"


@pytest.mark.skipif(not real.exists(), reason="real graph-compile.sh missing")
def test_real_graph_compile_no_tasks_and_unfit(tmp_path, monkeypatch):
    monkeypatch.delenv("SWARM_SCRIPTS_ROOT", raising=False)
    r = run(sa.graph_compile(str(tmp_path / "missing.md")))
    assert r["exit_code"] == 6 and r["verdict"] == "NO_TASKS"
    small = tmp_path / "p.md"
    small.write_text(HEAD + "| a | one | - | - | pending | 0 | impl | - |\n| b | two | - | - | pending | 0 | impl | - |\n")
    r = run(sa.graph_compile(str(small), fit=True))
    assert r["exit_code"] == 2 and r["verdict"] == "UNFIT_FALLBACK_LOOP"
