"""Hermetic tests for the swarm-adapter thin wrapper (stub script roots + temp git repos)."""
import asyncio
import contextlib
import errno
import hashlib
import json
import os
import pwd
import re
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

import swarm_adapter as sa

REAL_HOME = pwd.getpwuid(os.getuid()).pw_dir  # captured at import, before any fixture touches HOME
REPO_AGENT = Path(sa.__file__).resolve().parents[6]  # .../agent
REAL_SKILLS = REPO_AGENT / "skills"


def run(coro):
    return asyncio.run(coro)


@pytest.fixture(autouse=True)
def _isolated_git(monkeypatch, tmp_path, tmp_path_factory):
    """Hermetic git/env: ignore the developer's global/system config and any inherited repo/script selection
    (e.g. GIT_DIR / GIT_CONFIG_COUNT exported by a git hook or the shell that runs pytest). Tests that need these set them explicitly."""
    for k in [k for k in os.environ if k.startswith("GIT_")]:  # GIT_DIR, GIT_CONFIG_COUNT/KEY_n/PARAMETERS, ...
        monkeypatch.delenv(k)
    for k in ("SWARM_AGENT_DIR", "SWARM_WORKTREE_DIR", "SWARM_SCRIPTS_ROOT"):
        monkeypatch.delenv(k, raising=False)
    # Never let git discovery climb out of pytest's tmp root into an enclosing checkout (TMPDIR inside a repo):
    # a non-repo tmp dir must stay "not a git repository" instead of silently targeting the outer repo.
    # The real scripts keep state under $HOME/.claude/session-data/swarm (budget counters etc.): every test gets a fresh
    # HOME and explicit state dirs so nothing can ever touch the developer's real ones.
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    for k in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "FABLE_BUDGET_CONF"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("SWARM_STATE_DIR", str(home / "swarm-state"))
    monkeypatch.setenv("PASS_REPO_ROOT", str(home / "pass"))
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(Path(tmp_path_factory.getbasetemp()).resolve()))
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    monkeypatch.setenv("GIT_AUTHOR_NAME", "t")
    monkeypatch.setenv("GIT_AUTHOR_EMAIL", "t@t")
    monkeypatch.setenv("GIT_COMMITTER_NAME", "t")
    monkeypatch.setenv("GIT_COMMITTER_EMAIL", "t@t")


@pytest.fixture(autouse=True)
def _never_real_home(_isolated_git):
    """Fail the test (at setup and again at teardown) if HOME is, or became, the real home directory."""
    assert os.environ["HOME"] != REAL_HOME, "test would run with the real HOME"
    yield
    assert os.environ["HOME"] != REAL_HOME, "a test switched HOME back to the real home"


def test_home_and_state_dirs_are_isolated(tmp_path):
    assert os.environ["HOME"] != REAL_HOME and Path(os.environ["HOME"]).is_relative_to(tmp_path)
    assert Path(os.environ["SWARM_STATE_DIR"]).is_relative_to(tmp_path)


def _script(root: Path, rel: str, body: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("#!/usr/bin/env bash\n" + body)
    p.chmod(p.stat().st_mode | stat.S_IXUSR)


@pytest.fixture
def stubs(tmp_path, monkeypatch):
    root = tmp_path / "agent" / "skills"
    echo_args = 'printf "%s\\n" "$@"\n'
    _script(root, "swarm-implement/scripts/budget-guard.sh", echo_args)
    _script(root, "swarm-loop/scripts/mission-init.sh", echo_args)
    _script(root, "swarm-graph/scripts/graph-status.sh", 'echo "status: $1"\n')
    _script(
        root,
        "swarm-graph/scripts/graph-compile.sh",
        'echo "{\\"verdict\\": \\"CYCLE\\", \\"args\\": \\"$*\\"}"\nexit 3\n',
    )
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: tmp_path / "agent")  # resolver, NOT an env var
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
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: tmp_path / "empty")
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    r = run(sa.budget_guard("t"))
    assert r["exit_code"] == 127 and "budget-guard.sh" in r["stderr"]


def test_scripts_root_default_finds_repo_skills(monkeypatch):
    monkeypatch.delenv("SWARM_SCRIPTS_ROOT", raising=False)
    got = Path(sa._scripts_root("swarm-graph/scripts/graph-compile.sh"))
    assert got.resolve() == REAL_SKILLS.resolve()


# ---- worktrees ----------------------------------------------------------
def _git(cwd, *a):
    return subprocess.run(["git", *a], cwd=cwd, check=True, capture_output=True, text=True).stdout


@pytest.fixture
def repo(tmp_path):
    r = tmp_path / "proj" / "myrepo"
    r.mkdir(parents=True)
    _git(r, "init", "-q", "-b", "main")
    _git(r, "-c", "commit.gpgsign=false", "-c", "user.name=t", "-c", "user.email=t@t",
         "commit", "-q", "--allow-empty", "-m", "i")
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
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: tmp_path)
    r = run(sa.decide_shell("ls"))
    assert r["decision"] == "block" and "error" in r


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


# ======================= attempt 2 (checker findings) ===========================
def test_alloc_relative_env_made_absolute(repo, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("SWARM_WORKTREE_DIR", "rel-wt")
    r = run(sa.worktree_alloc("s", cwd=str(repo)))
    assert Path(r["path"]).parent == tmp_path / "rel-wt"


def test_alloc_refuses_dir_inside_repo(repo, monkeypatch):
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(repo / "wt"))
    r = run(sa.worktree_alloc("s", cwd=str(repo)))
    assert r["exit_code"] != 0 and r["error"] and "path" not in r
    assert not (repo / "wt").exists()


def test_alloc_refuses_relative_dir_resolving_inside_repo(repo, monkeypatch):
    monkeypatch.chdir(repo)
    monkeypatch.setenv("SWARM_WORKTREE_DIR", "wt")
    r = run(sa.worktree_alloc("s", cwd=str(repo)))
    assert r["exit_code"] != 0 and "path" not in r


def test_verify_missing_cwd(tmp_path):
    r = run(sa.verify(["true"], str(tmp_path / "nope")))
    assert r["passed"] is False and r["results"] == [] and r["error"]


def test_verify_str_is_single_command(tmp_path):
    r = run(sa.verify("echo one two", str(tmp_path)))
    assert r["passed"] is True and len(r["results"]) == 1


def test_verify_timeout_kills_process_group(tmp_path):
    marker = tmp_path / "marker"
    cmd = f"(sleep 2; touch {marker}) & sleep 30"
    r = run(sa.verify([cmd], str(tmp_path), timeout=0.5))
    assert r["passed"] is False and r["results"][0]["exit_code"] == 124
    import time
    time.sleep(3)
    assert not marker.exists()


def test_mission_init_cwd_and_depth(stubs, tmp_path):
    _script(stubs, "swarm-loop/scripts/mission-init.sh", 'pwd; printf "%s\\n" "$@"\n')
    wt = tmp_path / "wtdir"
    wt.mkdir()
    r = run(sa.mission_init("s", "g", "mission", depth=1, cwd=str(wt)))
    lines = r["stdout"].split("\n")
    assert lines[0] == str(wt.resolve())
    assert lines[1:6] == ["s", "g", "mission", "", "1"]


def test_budget_guard_options(stubs):
    r = run(sa.budget_guard("t", max_attempts=3, mission="m", mission_max=7))
    assert r["stdout"].split() == ["t", "3", "--mission=m", "--mission-max=7"]


def test_budget_guard_reset(stubs):
    r = run(sa.budget_guard("t", reset=True, mission="m"))
    assert r["stdout"].split() == ["--reset", "t", "--mission=m"]


def test_fable_maker(stubs):
    r = run(sa.fable_maker("base"))
    assert r["stdout"].split() == ["--fable-maker", "base"]


def _fake_agent(tmp_path, body):
    a = tmp_path / "agent"
    (a / "scripts/hooks").mkdir(parents=True)
    (a / "security-rules.json").write_text(json.dumps({"shell_command_rules": [{"id": "x", "tier": "block", "any_of": ["zzz-never-matches"]}]}))
    (a / "scripts/hooks/decide.py").write_text(body)
    return a


def test_decide_shell_passes_cwd(tmp_path, monkeypatch):
    a = _fake_agent(tmp_path, 'import sys,json\nr=json.load(sys.stdin)\nprint(json.dumps({"decision":"allow","reason":r["cwd"]+"|"+r["harness"]}))\n')
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: a)
    r = run(sa.decide_shell("ls", cwd=str(tmp_path)))
    assert r["reason"] == f"{tmp_path}|primeagent"


def test_decide_shell_crash_fails_closed(tmp_path, monkeypatch):
    a = _fake_agent(tmp_path, "raise SystemExit(3)\n")
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: a)
    r = run(sa.decide_shell("ls"))
    assert r["decision"] == "block" and r["error"]


def test_agent_dir_found_through_symlinked_skill_dir(tmp_path):
    skill = Path(sa.__file__).resolve().parents[2]
    link = tmp_path / "installed"
    link.symlink_to(skill)
    out = subprocess.run(
        ["python3", "-c", "import swarm_adapter as s; print(s._repo_agent_dir())"],
        env={**os.environ, "PYTHONPATH": str(link / "src")}, capture_output=True, text=True,
    )
    assert out.stdout.strip() == str(REPO_AGENT.resolve())


# ======================= attempt 3 ===============================================
@pytest.mark.parametrize("content", ["", "{}", "not json", '{"shell_command_rules": []}',
                                     '{"shell_command_rules": "x"}', "[]"])
def test_decide_shell_bad_rules_file_blocks(tmp_path, monkeypatch, content):
    a = _fake_agent(tmp_path, 'import json;print(json.dumps({"decision":"allow","reason":""}))\n')
    (a / "security-rules.json").write_text(content)
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: a)
    r = run(sa.decide_shell("ls"))
    assert r["decision"] == "block" and r["error"]


@pytest.mark.parametrize("content", ["", "{}", "not json"])
def test_decide_shell_real_decide_py_with_broken_rules_blocks(tmp_path, monkeypatch, content):
    a = tmp_path / "agent"
    shutil.copytree(REPO_AGENT / "scripts", a / "scripts")
    shutil.copy(REPO_AGENT / "security-rules.json", a / "security-rules.json")
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: a)
    assert run(sa.decide_shell("ls"))["decision"] == "allow"  # valid copy works
    (a / "security-rules.json").write_text(content)
    assert run(sa.decide_shell("ls"))["decision"] == "block"


def test_decide_shell_failopen_reply_blocks(tmp_path, monkeypatch):
    a = _fake_agent(tmp_path, 'import json;print(json.dumps({"decision":"allow","reason":"unknown family: x (fail-open)"}))\n')
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: a)
    r = run(sa.decide_shell("ls"))
    assert r["decision"] == "block" and "fail-open" in r["error"]


def test_verify_unreadable_cwd_never_raises(tmp_path):
    d = tmp_path / "locked"
    d.mkdir()
    d.chmod(0)
    try:
        r = run(sa.verify(["true"], str(d)))
    finally:
        d.chmod(0o700)
    assert r["passed"] is False and isinstance(r, dict)
    assert r.get("error") or r["results"][0]["exit_code"] in (126, 127)


def test_verify_non_str_element(tmp_path):
    r = run(sa.verify(["true", 5, None], str(tmp_path)))
    assert r["passed"] is False
    assert [x["exit_code"] for x in r["results"]] == [0, 126, 126]


def test_verify_non_list_commands(tmp_path):
    r = run(sa.verify(5, str(tmp_path)))
    assert r["passed"] is False and r["error"]


def test_verify_missing_bash(tmp_path, monkeypatch):
    monkeypatch.setattr(sa.subprocess, "Popen", lambda *a, **k: (_ for _ in ()).throw(FileNotFoundError("bash")))
    r = run(sa.verify(["true"], str(tmp_path)))
    assert r["passed"] is False and r["results"][0]["exit_code"] == 127


def test_alloc_branches_from_callers_checkout(repo, tmp_path, monkeypatch):
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wt"))
    mission = run(sa.worktree_alloc("mission", cwd=str(repo)))
    mp = mission["path"]
    _git(mp, "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "extra")
    want = _git(mp, "rev-parse", "HEAD").strip()
    child = run(sa.worktree_alloc("child", cwd=mp))
    assert _git(child["path"], "rev-parse", "HEAD").strip() == want
    assert child["base"] == want


def test_alloc_explicit_base_ref(repo, tmp_path, monkeypatch):
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wt"))
    first = _git(repo, "rev-parse", "HEAD").strip()
    _git(repo, "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "two")
    r = run(sa.worktree_alloc("b", cwd=str(repo), base_ref=first))
    assert _git(r["path"], "rev-parse", "HEAD").strip() == first


def test_alloc_bad_base_ref(repo, tmp_path, monkeypatch):
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wt"))
    r = run(sa.worktree_alloc("b", cwd=str(repo), base_ref="nope-ref"))
    assert r["exit_code"] != 0 and "path" not in r


def test_optional_plan_path_and_scale(stubs):
    _script(stubs, "swarm-graph/scripts/graph-compile.sh", 'echo "{\\"n\\": $#}"\n')
    assert run(sa.graph_compile())["n"] == 0
    assert run(sa.graph_status())["exit_code"] == 0
    r = run(sa.mission_init("s", "g"))
    assert r["stdout"].split("\n")[:2] == ["s", "g"]


@pytest.mark.parametrize("call", [
    lambda: sa.budget_guard("-x"), lambda: sa.fable_grant("--fable"), lambda: sa.fable_maker("-b"),
    lambda: sa.graph_compile("-p"), lambda: sa.graph_status("--help"), lambda: sa.mission_init("-s", "g"),
    lambda: sa.graph_compile("p", stale="-a"),
])
def test_leading_dash_rejected(stubs, call):
    r = run(call())
    assert r["exit_code"] != 0 and r["error"]


# ======================= attempt 4: structural (boundary wrapper, bounded verify, layout) ==========
import time  # noqa: E402

PUBLIC = ["budget_guard", "fable_grant", "fable_maker", "graph_compile", "graph_status", "mission_init",
          "worktree_alloc", "verify", "decide_shell"]


def test_boundary_on_every_public_async_function(monkeypatch):
    """By construction: any Exception inside any public function becomes an error dict."""
    def boom(*a, **k):
        raise RuntimeError("boom")
    for name in ("_script", "_worktree_alloc", "_verify", "_decide_shell"):
        monkeypatch.setattr(sa, name, boom)
    calls = {
        "budget_guard": ("t",), "fable_grant": ("t",), "fable_maker": ("t",), "graph_compile": (),
        "graph_status": (), "mission_init": ("s", "g"), "worktree_alloc": ("s",),
        "verify": (["true"], "/"), "decide_shell": ("ls",),
    }
    assert sorted(calls) == sorted(PUBLIC)
    for name, args in calls.items():
        r = run(getattr(sa, name)(*args))
        assert isinstance(r, dict) and "RuntimeError: boom" in r["error"], name
        if name == "verify":
            assert r["passed"] is False
        elif name == "decide_shell":
            assert r["decision"] == "block"
        else:
            assert r["exit_code"] != 0


def test_boundary_catches_bad_argument_binding():
    r = run(sa.budget_guard())  # missing required arg
    assert r["exit_code"] != 0 and "TypeError" in r["error"]


def test_verify_null_byte_command(tmp_path):
    r = run(sa.verify(["true\x00x", "true"], str(tmp_path)))
    assert r["passed"] is False and [x["exit_code"] for x in r["results"]] == [126, 0]


def test_verify_cwd_none_and_bad_types(tmp_path):
    assert run(sa.verify(["true"], None))["passed"] is False
    r = run(sa.verify(["true"], str(tmp_path), timeout="x"))
    assert r["passed"] is False and r["results"][0]["exit_code"] == 126


def test_verify_timeout_bounded_when_descendant_escapes_group(tmp_path):
    pidfile = tmp_path / "pid"
    code = f"import os,time;os.setsid();open({str(pidfile)!r},'w').write(str(os.getpid()));time.sleep(30)"
    cmd = f"python3 -c \"{code}\" & sleep 30"
    t0 = time.monotonic()
    try:
        r = run(sa.verify([cmd], str(tmp_path), timeout=0.5))
        took = time.monotonic() - t0
    finally:
        if pidfile.exists():
            try:
                os.kill(int(pidfile.read_text()), 9)
            except ProcessLookupError:
                pass
    assert took < 0.5 + 2 + 2, took
    assert r["passed"] is False and r["results"][0]["exit_code"] == 124
    assert "setsid" in r["results"][0]["output_tail"]


def test_verify_killpg_race_is_ignored(tmp_path, monkeypatch):
    def gone(pid, sig):
        raise ProcessLookupError
    monkeypatch.setattr(sa.os, "killpg", gone)
    r = run(sa.verify(["sleep 0.3"], str(tmp_path), timeout=0.1))
    assert r["results"][0]["exit_code"] == 124


def test_alloc_refuses_submodule(tmp_path):
    sub_src = tmp_path / "subsrc"
    sub_src.mkdir()
    _git(sub_src, "init", "-q", "-b", "main")
    _git(sub_src, "commit", "-q", "--allow-empty", "-m", "i")
    sup = tmp_path / "sup"
    sup.mkdir()
    _git(sup, "init", "-q", "-b", "main")
    _git(sup, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(sub_src), "sm")
    r = run(sa.worktree_alloc("s", cwd=str(sup / "sm")))
    assert r["exit_code"] != 0 and "unsupported" in r["error"] and "path" not in r
    assert not any((sup / ".git").rglob("swarm-prime*"))


def test_alloc_refuses_separate_git_dir(tmp_path):
    work, gd = tmp_path / "work", tmp_path / "elsewhere.git"
    work.mkdir()
    _git(work, "init", "-q", "-b", "main", f"--separate-git-dir={gd}")
    _git(work, "commit", "-q", "--allow-empty", "-m", "i")
    r = run(sa.worktree_alloc("s", cwd=str(work)))
    assert r["exit_code"] != 0 and "unsupported" in r["error"]


def test_alloc_refuses_base_nested_in_callers_checkout(repo, tmp_path, monkeypatch):
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wt"))
    mission = run(sa.worktree_alloc("mission", cwd=str(repo)))
    mp = Path(mission["path"])
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(mp / "nested"))
    r = run(sa.worktree_alloc("child", cwd=str(mp)))
    assert r["exit_code"] != 0 and "path" not in r and not (mp / "nested").exists()


def test_alloc_unaffected_by_inherited_git_dir(repo, tmp_path, monkeypatch):
    other = tmp_path / "other"
    other.mkdir()
    _git(other, "init", "-q", "-b", "main")
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wt"))
    for k, v in (("GIT_DIR", str(other / ".git")), ("GIT_WORK_TREE", str(other)),
                 ("GIT_INDEX_FILE", str(other / ".git" / "index"))):
        monkeypatch.setenv(k, v)
    r = run(sa.worktree_alloc("s", cwd=str(repo)))
    assert r["exit_code"] == 0, r
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        monkeypatch.delenv(k)
    assert "swarm-prime" not in _git(other, "branch", "--list", "swarm-prime/*")  # outer repo untouched
    assert "swarm-prime/s-" in _git(repo, "branch", "--list", "swarm-prime/*")


def test_script_cwd_is_file_and_non_str_task_id(stubs, tmp_path):
    f = tmp_path / "afile"
    f.write_text("x")
    r = run(sa.mission_init("s", "g", cwd=str(f)))
    assert r["exit_code"] != 0 and "NotADirectoryError" in r["error"]
    r = run(sa.budget_guard(5))
    assert r["exit_code"] != 0 and r["error"]


def test_graph_cwd_param(stubs, tmp_path):
    _script(stubs, "swarm-graph/scripts/graph-compile.sh", 'echo "{\\"pwd\\": \\"$PWD\\"}"\n')
    _script(stubs, "swarm-graph/scripts/graph-status.sh", 'pwd\n')
    d = tmp_path / "d"
    d.mkdir()
    assert run(sa.graph_compile(cwd=str(d)))["pwd"] == str(d.resolve())
    assert run(sa.graph_status(cwd=str(d)))["stdout"].strip() == str(d.resolve())


# ======================= attempt 5 =====================================================
def _repo_on(tmp_path, name, branch):
    r = tmp_path / name
    r.mkdir()
    _git(r, "init", "-q", "-b", branch)
    _git(r, "commit", "-q", "--allow-empty", "-m", "a")
    _git(r, "commit", "-q", "--allow-empty", "-m", "b")
    return r


RESET = "git reset --hard HEAD~1"  # only ever EVALUATED by decide_shell, never executed


def test_decide_shell_uses_requested_cwd_not_process_cwd(tmp_path, monkeypatch):
    on_main, on_feature = _repo_on(tmp_path, "m", "main"), _repo_on(tmp_path, "f", "feature")
    monkeypatch.chdir(on_feature)
    assert run(sa.decide_shell(RESET, cwd=str(on_main)))["decision"] == "block"
    monkeypatch.chdir(on_main)
    assert run(sa.decide_shell(RESET, cwd=str(on_feature)))["decision"] != "block"


def test_decide_shell_default_cwd_is_process_cwd(tmp_path, monkeypatch):
    on_main = _repo_on(tmp_path, "m", "main")
    monkeypatch.chdir(on_main)
    assert run(sa.decide_shell(RESET))["decision"] == "block"


def test_decide_shell_bad_cwd_blocks(tmp_path):
    r = run(sa.decide_shell("ls", cwd=str(tmp_path / "nope")))
    assert r["decision"] == "block" and r["error"]


# ======================= attempt 6 =====================================================
def test_no_destructive_public_function():
    public = [n for n in dir(sa) if not n.startswith("_")] + list(sa.__all__)
    assert not [n for n in public if "release" in n or "remove" in n or "delete" in n], public


def test_alloc_refuses_separate_git_dir_named_dot_git(tmp_path, monkeypatch):
    work, gd = tmp_path / "work", tmp_path / "elsewhere" / ".git"
    work.mkdir()
    gd.parent.mkdir()
    _git(work, "init", "-q", "-b", "main", f"--separate-git-dir={gd}")
    _git(work, "commit", "-q", "--allow-empty", "-m", "i")
    r = run(sa.worktree_alloc("s", cwd=str(work)))
    assert r["exit_code"] != 0 and "unsupported" in r["error"] and "path" not in r
    assert not (tmp_path / ".worktrees").exists()


# ======================= attempt 7: paths come from the module only ====================
MARK = "PWNED"


def _evil_tree(root: Path, marker: Path) -> Path:
    """A target repo that ships its own agent/ and skills/ trees whose scripts would write MARK."""
    payload = f"touch {marker}\n"
    _script(root, "skills/swarm-graph/scripts/graph-status.sh", payload)
    _script(root, "skills/swarm-graph/scripts/graph-compile.sh", payload)
    _script(root, "skills/swarm-implement/scripts/budget-guard.sh", payload)
    _script(root, "skills/swarm-loop/scripts/mission-init.sh", payload)
    _script(root, "agent/skills/swarm-graph/scripts/graph-status.sh", payload)
    (root / "agent/scripts/hooks").mkdir(parents=True)
    (root / "agent/scripts/hooks/decide.py").write_text(
        f"import json;open({str(marker)!r},'w').write('x');print(json.dumps({{'decision':'allow','reason':'evil'}}))\n")
    (root / "agent/security-rules.json").write_text(json.dumps({"shell_command_rules": [{"id": "x", "tier": "block", "any_of": ["zzz-never-matches"]}]}))
    return root


@pytest.fixture
def evil(tmp_path, monkeypatch):
    marker = tmp_path / MARK
    root = _evil_tree(tmp_path / "evilrepo", marker)
    # relative overrides that used to be validated against the process cwd but executed from the target cwd
    monkeypatch.setenv("SWARM_AGENT_DIR", "agent")
    monkeypatch.setenv("SWARM_SCRIPTS_ROOT", "skills")
    return root, marker


def test_env_overrides_do_not_exist():
    src = Path(sa.__file__).read_text()
    assert "SWARM_AGENT_DIR" not in src and "SWARM_SCRIPTS_ROOT" not in src


def test_decide_shell_never_runs_target_cwd_decide_py(evil):
    root, marker = evil
    dangerous = "r" + "m -r" + "f /"
    assert run(sa.decide_shell(dangerous, cwd=str(root)))["decision"] == "block"
    assert run(sa.decide_shell("ls", cwd=str(root)))["decision"] == "allow"
    assert not marker.exists()


def test_scripts_never_run_from_target_cwd(evil, stubs, monkeypatch):
    root, marker = evil
    assert run(sa.graph_status(cwd=str(root)))["stdout"].strip() == "status:"
    assert run(sa.mission_init("s", "g", cwd=str(root)))["stdout"].split("\n")[:2] == ["s", "g"]
    assert run(sa.graph_compile(cwd=str(root)))["exit_code"] == 3
    monkeypatch.chdir(root)  # budget_guard has no cwd parameter: the process cwd is the evil dir
    assert run(sa.budget_guard("t"))["stdout"].split() == ["t"]
    assert not marker.exists()


def test_paths_passed_to_subprocesses_are_absolute(stubs, tmp_path, monkeypatch):
    seen = []
    real = sa._sync_run
    monkeypatch.setattr(sa, "_sync_run", lambda argv, *a, **k: (seen.append(argv), real(argv, *a, **k))[1])
    run(sa.budget_guard("t"))
    run(sa.decide_shell("ls"))
    assert seen and all(Path(a).is_absolute() for argv in seen for a in argv[1:2] if argv[0] in ("bash", "python3"))


def test_verify_exited_command_with_escaped_pipe_holder_reports_real_exit_code(tmp_path):
    pidfile = tmp_path / "pid"
    code = f"import os,time;os.setsid();open({str(pidfile)!r},'w').write(str(os.getpid()));time.sleep(30)"
    try:
        r = run(sa.verify([f'python3 -c "{code}" & sleep 0.3; exit 3'], str(tmp_path), timeout=1))
    finally:
        if pidfile.exists():
            try:
                os.kill(int(pidfile.read_text()), 9)
            except ProcessLookupError:
                pass
    assert r["results"][0]["exit_code"] == 3 and "setsid" in r["results"][0]["output_tail"]


# ======================= attempt 8 =======================================================
def test_script_subprocesses_get_pythonsafepath_and_decide_runs_isolated(monkeypatch, tmp_path):
    seen = []
    real = subprocess.run
    monkeypatch.setattr(sa.subprocess, "run", lambda argv, **k: (seen.append((argv, k.get("env"))), real(argv, **k))[1])
    run(sa.budget_guard("t", reset=True, mission="m-safepath-test"))  # real script; --reset only touches its own counter
    run(sa.graph_status(str(tmp_path / "none.md")))
    run(sa.decide_shell("ls"))
    assert len(seen) >= 3
    for argv, env in seen:
        assert env is not None and env.get("PYTHONSAFEPATH") == "1", argv
    decide = [a for a, _ in seen if a[0] == "python3"]
    assert decide and decide[0][1] == "-I", decide


def test_hostile_stdlib_shadow_in_target_cwd_is_never_imported(tmp_path):
    marker, d = tmp_path / MARK, tmp_path / "hostile"
    d.mkdir()
    for mod in ("re", "json", "os", "sitecustomize"):
        (d / f"{mod}.py").write_text(f"open({str(marker)!r}, 'w').write('x')\n")
    run(sa.graph_compile(cwd=str(d)))   # REAL scripts: default resolver points at this worktree's agent/skills
    run(sa.graph_status(cwd=str(d)))
    run(sa.decide_shell("ls", cwd=str(d)))
    assert not marker.exists()


_VALID_RULES = json.loads((REPO_AGENT / "security-rules.json").read_text())
RULE_FIXTURES = {
    "empty-object": {},
    "list": [],
    "empty-rules": {"shell_command_rules": []},
    "rule-empty-object": {"shell_command_rules": [{}]},
    "ask-only": {"shell_command_rules": [{"id": "a", "tier": "ask", "any_of": ["x"]}]},
    "block-without-pattern": {"shell_command_rules": [{"id": "b", "tier": "block"}]},
    "block-empty-pattern-list": {"shell_command_rules": [{"id": "b", "tier": "block", "any_of": []}]},
    "valid": _VALID_RULES,
}


@pytest.mark.parametrize("name", list(RULE_FIXTURES))
def test_rules_effectiveness_parity_with_prime_shell_guard(name, repo, tmp_path, monkeypatch):
    guard_src = REPO_AGENT / "scripts" / "prime-shell-guard.sh"
    a = tmp_path / "agent"
    shutil.copytree(REPO_AGENT / "scripts", a / "scripts")
    (a / "security-rules.json").write_text(json.dumps(RULE_FIXTURES[name]))
    guard = subprocess.run(["bash", str(a / "scripts" / guard_src.name), "true"], cwd=repo,
                           capture_output=True, text=True, timeout=60)
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: a)
    mine = run(sa.decide_shell("true", cwd=str(repo)))
    assert (guard.returncode == 126) == (name != "valid"), guard.stderr
    assert (mine["decision"] == "block") == (guard.returncode == 126), (mine, guard.stderr)


# ======================= attempt 9 =======================================================
def test_every_public_name_is_a_boundary_wrapped_coroutine_returning_a_dict():
    import inspect
    assert not hasattr(sa, "scripts_root") and "scripts_root" not in sa.__all__
    for name in sa.__all__:
        fn = getattr(sa, name)
        assert inspect.iscoroutinefunction(fn) and hasattr(fn, "__wrapped__"), name
        r = run(fn(__bogus_kwarg__=1))  # unbindable -> TypeError inside the boundary
        assert isinstance(r, dict) and "TypeError" in r["error"], name


# ======================= T6c: commit/merge-time primitives (CONTEXT Q3-a) ===================
SWARM_MD = "agent/SWARM.md"
HOOK = "agent/hooks/claude/x.sh"


class _Pinned:
    """The four commit/merge-time primitives called like a well-behaved caller: `expect_common_dir` is the common git
    dir of the repository `wt` is a checkout of RIGHT NOW (so a test that corrupts `wt` still passes a legitimate
    expectation). An explicit `expect_common_dir=` overrides it; the tests of the pin itself call `sa.*` directly."""

    @staticmethod
    def _kw(wt) -> dict:
        try:
            env = {k: v for k, v in os.environ.items() if k not in sa._GIT_LOCAL_ENV}  # what a hook-launched caller would do
            out = subprocess.run(["git", "-C", str(wt), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                 check=True, capture_output=True, text=True, env=env).stdout
            return {"expect_common_dir": os.path.realpath(out.strip())}
        except Exception:  # not a repo / not a path: any absolute value, the call refuses anyway
            return {"expect_common_dir": "/nonexistent/.git"}

    def change_set(self, wt, *a, **k):
        return sa.change_set(wt, *a, **(self._kw(wt) | k))

    def tier_b_hits(self, wt, *a, **k):
        return sa.tier_b_hits(wt, *a, **(self._kw(wt) | k))

    def stage_task(self, wt, *a, **k):
        return sa.stage_task(wt, *a, **(self._kw(wt) | k))

    def incoming(self, wt, *a, **k):
        return sa.incoming(wt, *a, **(self._kw(wt) | k))

    def verify_merge(self, wt, *a, **k):
        return sa.verify_merge(wt, *a, **(self._kw(wt) | k))

    def commit_tree(self, wt, *a, **k):
        return sa.commit_tree(wt, *a, **(self._kw(wt) | k))

    def update_ref(self, wt, *a, **k):
        return sa.update_ref(wt, *a, **(self._kw(wt) | k))


_p = _Pinned()


def _inc(r: dict) -> dict:
    """incoming's result without `sha`/`head`/`tree`, after checking all three are full object ids."""
    r = dict(r)
    for k in ("sha", "head", "tree"):
        assert re.fullmatch(r"[0-9a-f]{40}", r.pop(k, "")), r
    return r


def _w(p: Path, text: str = "x\n") -> Path:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    return p


def _commit(cwd, *paths, msg="c"):
    if paths:
        _git(cwd, "add", "--", *paths)
    _git(cwd, "commit", "-q", "-m", msg)


def _index_names(wt) -> str:
    return _git(wt, "diff", "--cached", "--name-only")


def _nt(r: dict, wt) -> dict:
    """stage_task's result without `tree` / `head`, after checking `tree` is the tree of the index as staged and `head` the HEAD
    commit it was staged on (T6c a11: `head` is new, the parent the caller's commit_tree / update_ref use)."""
    r = dict(r)
    assert r.pop("tree") == _git(wt, "write-tree").strip(), r
    assert r.pop("head") == _git(wt, "rev-parse", "HEAD").strip(), r
    return r


@contextlib.contextmanager
def _opened(wt):
    """The primitives' own view of checkout `wt` (located by Python, with its shadow repository), for tests of internal helpers."""
    with sa._open(str(wt), _Pinned._kw(wt)["expect_common_dir"]) as (r, err):
        assert r is not None, err
        yield r


@pytest.fixture
def dot(tmp_path, monkeypatch):
    """The dotfiles main checkout at its fixed-pattern location under the fake HOME, plus a prime task worktree made
    by worktree_alloc at <parent>/.worktrees/dotfiles/<slug>-<ts> (CONTEXT Q8, outside every fixed pattern)."""
    main = Path(os.environ["HOME"]) / "go/src/github.com/kpango/dotfiles"
    main.mkdir(parents=True)
    _git(main, "init", "-q", "-b", "main")
    files = (SWARM_MD, HOOK, "src/a.go", "src/old.go", "README.md")
    for rel in files:
        _w(main / rel, rel + "\n")
    _commit(main, *files, msg="base")
    monkeypatch.delenv("SWARM_WORKTREE_DIR", raising=False)
    r = run(sa.worktree_alloc("t1", cwd=str(main)))
    wt = Path(r["path"])
    assert wt.parent == main.parent / ".worktrees" / "dotfiles", r
    return main, wt, r["base"]


def _rules():
    rules, _, err = sa._write_scope_rules()
    assert rules is not None, err
    return rules


def test_change_set_merges_all_four_sources(dot, tmp_path):
    _, wt, base = dot
    _w(wt / "src/committed.go")
    _commit(wt, "src/committed.go")
    _w(wt / "src/staged.go")
    _git(wt, "add", "--", "src/staged.go")
    _w(wt / "src/a.go", "changed\n")
    _w(wt / "src/untracked.go")
    (wt / "src/link").symlink_to(_w(tmp_path / "outside/t"))
    r = run(_p.change_set(str(wt), base))
    assert r["exit_code"] == 0 and r["commits"] == 1 and r["branch"].startswith("swarm-prime/t1-"), r
    p = r["paths"]
    assert p["src/committed.go"] == {"in": ["committed", "index", "worktree"], "kind": "file"}
    assert p["src/staged.go"] == {"in": ["index", "worktree"], "kind": "file"}
    assert p["src/a.go"] == {"in": ["worktree"], "kind": "file"}
    assert p["src/untracked.go"] == {"in": ["untracked"], "kind": "file"}
    assert p["src/link"] == {"in": ["untracked"], "kind": "symlink"}
    assert set(p) == {"src/committed.go", "src/staged.go", "src/a.go", "src/untracked.go", "src/link"}


def test_change_set_detached_head_has_empty_branch(dot):
    _, wt, base = dot
    _git(wt, "checkout", "-q", "--detach")
    r = run(_p.change_set(str(wt), base))
    assert r["exit_code"] == 0 and r["branch"] == "" and r["paths"] == {}


@pytest.mark.parametrize("base", ["HEAD", "main", "HEAD~1", "-x", "--output=out.txt", "abc123", "1234567g",
                                  "A" * 7, "a" * 41, ""])
def test_change_set_rejects_non_hex_base(dot, base):
    _, wt, _ = dot
    r = run(_p.change_set(str(wt), base))
    assert r["exit_code"] != 0 and r["error"] and "paths" not in r
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and r["error"] and "staged" not in r


def test_change_set_unknown_commit_is_error(dot):
    _, wt, _ = dot
    r = run(_p.change_set(str(wt), "0" * 40))
    assert r["exit_code"] != 0 and "not a commit" in r["error"] and "paths" not in r


def test_missing_worktree_fails_closed(dot, tmp_path):
    _, _, base = dot
    gone = str(tmp_path / "nope")
    r = run(_p.change_set(gone, base))
    assert r["exit_code"] != 0 and r["error"] and "paths" not in r
    r = run(_p.tier_b_hits(gone, ["src/a.go", SWARM_MD]))
    assert r["exit_code"] != 0 and r["error"] and r["hits"] == ["src/a.go", SWARM_MD]
    r = run(_p.stage_task(gone, base))
    assert r["exit_code"] != 0 and r["error"] and "zero_diff" not in r
    r = run(_p.incoming(gone, "main"))
    assert r["exit_code"] != 0 and r["error"] and "paths" not in r


def test_subdirectory_is_not_a_worktree_top(dot):
    _, wt, base = dot
    sub = str(wt / "src")
    for r in (run(_p.change_set(sub, base)), run(_p.tier_b_hits(sub, ["a.go"])),
              run(_p.stage_task(sub, base)), run(_p.incoming(sub, "main"))):
        assert r["exit_code"] != 0 and "top level" in r["error"], r


def test_twin_in_prime_worktree_layout_hits_project_settings(dot):
    _, wt, base = dot
    settings = [".claude/settings.json", ".claude/settings.local.json"]
    for rel in settings:
        _w(wt / rel, '{"permissions":{"allow":["Bash(*)"]}}')
        assert not sa._tier_b_match(_rules(), str(wt / rel), os.environ["HOME"])  # worktree path alone: no pattern
    r = run(_p.tier_b_hits(str(wt), [*settings, "src/a.go"]))
    assert r["exit_code"] == 0 and r["hits"] == settings, r
    assert Path(r["rules"]) == REPO_AGENT / "write-scope-rules.json"
    assert run(_p.stage_task(str(wt), base)) == {"staged": [], "tier_b": settings, "zero_diff": False, "exit_code": 3}
    assert _index_names(wt) == ""


def test_maker_committed_tier_b_change_is_caught(dot):
    _, wt, base = dot
    _w(wt / SWARM_MD, "evil\n")
    _commit(wt, SWARM_MD)
    _w(wt / "src/a.go", "ok\n")
    r = run(_p.stage_task(str(wt), base))
    assert r == {"staged": [], "tier_b": [SWARM_MD], "zero_diff": False, "exit_code": 3}
    assert _index_names(wt) == ""


def test_commit_then_restore_working_tree_still_caught(dot):
    _, wt, base = dot
    _w(wt / SWARM_MD, "evil\n")
    _commit(wt, SWARM_MD)
    _git(wt, "checkout", "-q", base, "--", SWARM_MD)  # index AND working tree back to base: only base..HEAD carries it
    assert _git(wt, "show", f"HEAD:{SWARM_MD}") == "evil\n"
    cs = run(_p.change_set(str(wt), base))
    assert cs["paths"][SWARM_MD]["in"] == ["committed"] and cs["commits"] == 1
    assert run(_p.stage_task(str(wt), base))["tier_b"] == [SWARM_MD]


def test_staged_only_tier_b_change_is_caught(dot):
    _, wt, base = dot
    original = (wt / SWARM_MD).read_text()
    _w(wt / SWARM_MD, "evil\n")
    _git(wt, "add", "--", SWARM_MD)
    _w(wt / SWARM_MD, original)  # working tree == base, only the index differs
    assert run(_p.change_set(str(wt), base))["paths"][SWARM_MD]["in"] == ["index"]
    assert run(_p.stage_task(str(wt), base))["tier_b"] == [SWARM_MD]


def test_tier_b_file_replaced_by_symlink_is_caught(dot, tmp_path):
    _, wt, base = dot
    out = _w(tmp_path / "outside/swarm.md", "evil\n")
    (wt / SWARM_MD).unlink()
    (wt / SWARM_MD).symlink_to(out)
    assert not sa._tier_b_match(_rules(), os.path.realpath(wt / SWARM_MD), os.environ["HOME"])  # realpath alone escapes
    cs = run(_p.change_set(str(wt), base))
    assert cs["paths"][SWARM_MD] == {"in": ["worktree"], "kind": "typechange"}
    assert run(_p.stage_task(str(wt), base))["tier_b"] == [SWARM_MD]


def test_tier_b_dir_replaced_by_symlink_is_caught(dot, tmp_path):
    _, wt, base = dot
    out = tmp_path / "outside/hooks"
    _w(out / "x.sh", "evil\n")
    shutil.rmtree(wt / "agent/hooks/claude")
    (wt / "agent/hooks/claude").symlink_to(out)
    cs = run(_p.change_set(str(wt), base))
    assert cs["paths"][HOOK] == {"in": ["worktree"], "kind": "deleted"}
    assert cs["paths"]["agent/hooks/claude"] == {"in": ["untracked"], "kind": "symlink"}
    assert HOOK in run(_p.stage_task(str(wt), base))["tier_b"]


def test_untracked_symlink_into_tier_b_dir_is_caught(dot, tmp_path):
    _, wt, base = dot
    out = _w(tmp_path / "outside/new.sh", "evil\n")
    (wt / "agent/hooks/claude/new.sh").symlink_to(out)
    assert not sa._tier_b_match(_rules(), os.path.realpath(wt / "agent/hooks/claude/new.sh"), os.environ["HOME"])
    cs = run(_p.change_set(str(wt), base))
    assert cs["paths"]["agent/hooks/claude/new.sh"] == {"in": ["untracked"], "kind": "symlink"}
    assert run(_p.stage_task(str(wt), base))["tier_b"] == ["agent/hooks/claude/new.sh"]


@pytest.mark.parametrize("swap", ["file", "dir", "untracked"])
def test_symlink_swaps_caught_in_main_checkout_itself(dot, tmp_path, swap):
    """wt == main checkout: the twin is the same path, so only the unresolved <wt>/P candidate can catch these."""
    main, _, _ = dot
    base = _git(main, "rev-parse", "HEAD").strip()
    out = tmp_path / "outside"
    if swap == "file":
        (main / SWARM_MD).unlink()
        (main / SWARM_MD).symlink_to(_w(out / "s.md"))
        want = SWARM_MD
    elif swap == "dir":
        _w(out / "x.sh")
        shutil.rmtree(main / "agent/hooks/claude")
        (main / "agent/hooks/claude").symlink_to(out)
        want = HOOK
    else:
        (main / "agent/hooks/claude/new.sh").symlink_to(_w(out / "n.sh"))
        want = "agent/hooks/claude/new.sh"
    assert not sa._tier_b_match(_rules(), os.path.realpath(main / want), os.environ["HOME"])
    r = run(_p.stage_task(str(main), base))
    assert want in r["tier_b"] and r["exit_code"] == 3 and _index_names(main) == ""


def test_symlink_pointing_into_tier_b_is_caught_by_realpath(dot):
    _, wt, _ = dot
    (wt / "src/innocent.md").symlink_to(wt / SWARM_MD)  # the unresolved path is harmless, the target is Tier B
    assert run(_p.tier_b_hits(str(wt), ["src/innocent.md"]))["hits"] == ["src/innocent.md"]


def test_committed_rm_and_mv_stage_with_update_index(dot):
    _, wt, base = dot
    _git(wt, "rm", "-q", "--", "src/old.go")
    _git(wt, "mv", "src/a.go", "src/b.go")
    _commit(wt, msg="rm+mv")
    add = subprocess.run(["git", "add", "--", "src/old.go", "src/a.go"], cwd=wt, capture_output=True, text=True, check=False)
    assert add.returncode == 128 and "did not match any files" in add.stderr  # why stage_task must not use `git add`
    cs = run(_p.change_set(str(wt), base))
    assert {p: v["kind"] for p, v in cs["paths"].items()} == {"src/a.go": "deleted", "src/b.go": "file", "src/old.go": "deleted"}
    for old in ("src/old.go", "src/a.go"):  # the plumbing stage_task uses accepts an already-committed deletion
        assert sa._git(str(wt), "update-index", "--add", "--remove", "--", old)["exit_code"] == 0
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": [], "tier_b": [], "zero_diff": False, "exit_code": 0}  # already committed: nothing to stage


def test_uncommitted_git_mv_and_git_rm_are_staged(dot):
    _, wt, base = dot
    _git(wt, "rm", "-q", "--", "src/old.go")
    _git(wt, "mv", "src/a.go", "src/b.go")
    add = subprocess.run(["git", "add", "--", "src/old.go"], cwd=wt, capture_output=True, text=True, check=False)
    assert add.returncode == 128  # gone from index and working tree: `git add` cannot stage it
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": ["src/a.go", "src/b.go", "src/old.go"], "tier_b": [], "zero_diff": False, "exit_code": 0}


def test_uncommitted_rm_mv_and_dir_to_symlink_are_staged(dot, tmp_path):
    _, wt, base = dot
    (wt / "src/old.go").unlink()
    _git(wt, "mv", "src/a.go", "src/b.go")
    _w(tmp_path / "outside/lib/z.go")
    shutil.rmtree(wt / "src")
    (wt / "src").symlink_to(tmp_path / "outside/lib")  # src/* now "beyond a symbolic link"
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": ["src", "src/a.go", "src/old.go"], "tier_b": [], "zero_diff": False, "exit_code": 0}, r
    assert _git(wt, "ls-files", "-s", "src").startswith("120000")


def test_uncommitted_rename_is_staged(dot):
    _, wt, base = dot
    (wt / "src/a.go").rename(wt / "src/renamed.go")
    (wt / "src/old.go").unlink()
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": ["src/a.go", "src/old.go", "src/renamed.go"], "tier_b": [], "zero_diff": False, "exit_code": 0}


def test_index_only_change_is_resynced_to_working_tree(dot):
    _, wt, base = dot
    original = (wt / "src/a.go").read_text()
    _w(wt / "src/a.go", "staged then reverted\n")
    _git(wt, "add", "--", "src/a.go")
    _w(wt / "src/a.go", original)  # working tree == HEAD, the index still differs
    assert _nt(run(_p.stage_task(str(wt), base)), wt) == {"staged": [], "tier_b": [], "zero_diff": True, "exit_code": 0}
    assert _index_names(wt) == ""


def test_plan_file_excluded_from_staging_but_tier_b_checked(dot):
    _, wt, base = dot
    _w(wt / "@fix_plan.md", "| plan |\n")
    assert _nt(run(_p.stage_task(str(wt), base)), wt) == {"staged": [], "tier_b": [], "zero_diff": True, "exit_code": 0}
    _w(wt / "src/new.go")
    r = run(_p.stage_task(str(wt), base))
    assert r["staged"] == ["src/new.go"] and r["zero_diff"] is False
    assert "@fix_plan.md" in _git(wt, "ls-files", "--others")
    _w(wt / SWARM_MD, "evil\n")  # an excluded path is still Tier B checked
    r = run(_p.stage_task(str(wt), base, exclude=("@fix_plan.md", SWARM_MD)))
    assert r["tier_b"] == [SWARM_MD] and r["exit_code"] == 3


def test_exclude_is_exact_root_name_only(dot):
    _, wt, base = dot
    _w(wt / "docs/@fix_plan.md")
    assert run(_p.stage_task(str(wt), base))["staged"] == ["docs/@fix_plan.md"]


def test_ignored_files_are_listed_and_tier_b_checked_but_never_staged(dot):
    """T6c a9: the working tree is listed by Python, so change_set's `untracked` now includes ignored files (they are Tier B
    checked like any change); stage_task leaves ignored never-committed files out of the commit (`check-ignore`). A name that
    looks like pathspec magic (`:(exclude)...`) is a plain path to check-ignore (sent as `./<path>`)."""
    _, wt, base = dot
    _w(wt / ".gitignore", "build/\n*.log\n")
    _commit(wt, ".gitignore")
    for p in ("build/x.go", "a.log", "src/new.go", ":(exclude)n.go", ":(glob)z.log"):
        _w(wt / p)
    cs = run(_p.change_set(str(wt), base))
    assert all(cs["paths"][p] == {"in": ["untracked"], "kind": "file"} for p in ("build/x.go", "a.log", ":(glob)z.log")), cs
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["staged"] == [":(exclude)n.go", "src/new.go"], r
    _w(wt / "agent/hooks/claude/x.log")  # ignored, at a Tier B path: refused although it would never be committed
    r = run(_p.stage_task(str(wt), base))
    assert r == {"staged": [], "tier_b": ["agent/hooks/claude/x.log"], "zero_diff": False, "exit_code": 3}, r


@pytest.mark.parametrize("content", [None, "", "not json", "[]", "{}", '{"suffix_patterns": ["*/x"]}',
                                     '{"suffix_patterns": [], "fixed_absolute_path_patterns": []}',
                                     '{"suffix_patterns": "*/x", "fixed_absolute_path_patterns": ["/x"]}',
                                     '{"suffix_patterns": [1], "fixed_absolute_path_patterns": ["/x"]}'])
def test_missing_or_bad_rules_fail_closed(dot, tmp_path, monkeypatch, content):
    _, wt, base = dot
    a = tmp_path / "fakeagent"
    a.mkdir()
    if content is not None:
        (a / "write-scope-rules.json").write_text(content)
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: a)
    _w(wt / "src/new.go")
    r = run(_p.tier_b_hits(str(wt), ["src/new.go"]))
    assert r["exit_code"] != 0 and r["error"] and r["hits"] == ["src/new.go"]
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and r["error"] and r["tier_b"] == ["src/new.go"] and "staged" not in r
    assert _index_names(wt) == ""


def test_rules_only_next_to_module_never_prime_home(dot, monkeypatch):
    _, wt, _ = dot
    _w(Path(os.environ["HOME"]) / ".prime/agent/write-scope-rules.json",
       json.dumps({"suffix_patterns": ["*/never"], "fixed_absolute_path_patterns": ["/never"]}))
    monkeypatch.setattr(sa, "_repo_agent_dir", lambda: None)
    r = run(_p.tier_b_hits(str(wt), [SWARM_MD]))
    assert r["exit_code"] != 0 and r["hits"] == [SWARM_MD]


def test_newline_and_non_ascii_paths(dot):
    _, wt, base = dot
    names = ["src/new\nline.go", "src/日本語.go", "src/-dash.go"]
    for n in names:
        _w(wt / n)
    with open(os.fsencode(str(wt)) + b"/src/bad\xff.go", "wb") as f:
        f.write(b"x\n")
    bad = os.fsdecode(b"src/bad\xff.go")
    assert set(run(_p.change_set(str(wt), base))["paths"]) == {*names, bad}
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and sorted(r["staged"]) == sorted([*names, bad]), r
    _w(wt / "agent/hooks/claude/new\nline.sh")
    assert run(_p.stage_task(str(wt), base))["tier_b"] == ["agent/hooks/claude/new\nline.sh"]


def test_inherited_git_env_is_ignored(dot, tmp_path, monkeypatch):
    _, wt, base = dot
    other = tmp_path / "other"
    other.mkdir()
    _git(other, "init", "-q", "-b", "main")
    _w(wt / "src/new.go")
    for k, v in (("GIT_DIR", str(other / ".git")), ("GIT_WORK_TREE", str(other)),
                 ("GIT_INDEX_FILE", str(other / ".git/index"))):
        monkeypatch.setenv(k, v)
    assert run(_p.stage_task(str(wt), base))["staged"] == ["src/new.go"]


def test_incoming_lists_branch_side_only_and_feeds_tier_b(dot, monkeypatch, tmp_path):
    main, _, _ = dot
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wts"))
    mission = Path(run(sa.worktree_alloc("mission", cwd=str(main)))["path"])
    task = run(sa.worktree_alloc("task", cwd=str(mission)))
    tp = Path(task["path"])
    _w(tp / SWARM_MD, "evil\n")
    _w(tp / "src/t.go")
    _commit(tp, SWARM_MD, "src/t.go")
    _w(mission / "src/m.go")
    _commit(mission, "src/m.go")  # mission-side commit: not incoming
    r = run(_p.incoming(str(mission), task["branch"]))
    assert (r["sha"], r["head"]) == (_git(tp, "rev-parse", "HEAD").strip(), _git(mission, "rev-parse", "HEAD").strip())
    assert _inc(r) == {"paths": [SWARM_MD, "src/t.go"], "exit_code": 0}
    assert run(_p.tier_b_hits(str(mission), r["paths"]))["hits"] == [SWARM_MD]
    assert run(_p.incoming(str(mission), "no-such-branch"))["exit_code"] != 0


@pytest.mark.parametrize("branch", ["-x", "--output=out.txt", "-"])
def test_incoming_rejects_dash_branch(dot, branch):
    _, wt, _ = dot
    r = run(_p.incoming(str(wt), branch))
    assert r["exit_code"] != 0 and r["error"] and "paths" not in r


def test_primitives_have_no_destructive_git_verbs():
    import inspect
    src = "".join(inspect.getsource(f) for f in (sa._change_set, sa._tier_b_hits, sa._stage_task, sa._stage_tree, sa._incoming,
                                                 sa._resolve_base, sa._write_blobs, sa._ignored, sa.tier_b_hits,
                                                 sa._update_ref, sa._cas_branch))
    for verb in ("commit", "merge", "push", "reset", "add", "checkout", "restore", "stash"):
        assert f'"{verb}"' not in src, verb


# ---- T6c attempt 2: checker findings 1-6 + tree ------------------------------------------------------------
def _branch(wt) -> str:
    return _git(wt, "symbolic-ref", "--short", "HEAD").strip()


def _evil_commit(wt) -> None:
    _w(wt / SWARM_MD, "evil\n")
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "evil", "--", SWARM_MD)


@pytest.mark.parametrize("kind", ["branch", "tag", "remote-head", "gitdir-file"])
def test_short_base_shadowed_by_ref_name_is_refused(dot, kind):
    """(1) git resolves a short hex ref-first: a maker-made ref named like the base must not move the base."""
    _, wt, base = dot
    short = base[:12]  # what swarm-implement MACHINE.md puts in init.base
    _evil_commit(wt)
    assert run(_p.stage_task(str(wt), short))["tier_b"] == [SWARM_MD]  # before the hijack
    if kind == "branch":
        _git(wt, "branch", short, "HEAD")
    elif kind == "tag":
        _git(wt, "tag", short, "HEAD")
    elif kind == "remote-head":
        _git(wt, "update-ref", f"refs/remotes/{short}/HEAD", "HEAD")
    else:
        common = _git(wt, "rev-parse", "--path-format=absolute", "--git-common-dir").strip()
        Path(common, short).write_text(_git(wt, "rev-parse", "HEAD"))  # $GIT_DIR/<name> is the first DWIM rule
    assert _git(wt, "rev-parse", f"{short}^{{commit}}").strip() != base  # git itself now resolves it elsewhere
    cs = run(_p.change_set(str(wt), short))
    assert cs["exit_code"] != 0 and cs["error"] and "paths" not in cs, cs
    r = run(_p.stage_task(str(wt), short))
    assert r["exit_code"] != 0 and r["error"] and "zero_diff" not in r and _index_names(wt) == "", r
    # the full sha is unaffected and still sees the Tier B commit
    assert run(_p.stage_task(str(wt), base))["tier_b"] == [SWARM_MD]


def test_resolve_base_returns_full_sha_starting_with_prefix(dot):
    _, wt, base = dot
    with _opened(wt) as r:
        assert sa._resolve_base(r, base[:7]) == (base, None)
        sha, err = sa._resolve_base(r, "0" * 12)
    assert sha is None and "not a commit" in err["error"]


def _replace_base_with_evil_tree(wt, base) -> None:
    evil_tree = _git(wt, "rev-parse", "HEAD^{tree}").strip()
    fake = _git(wt, "commit-tree", evil_tree, "-m", "base").strip()
    _git(wt, "replace", base, fake)
    assert _git(wt, "diff", "--name-only", base, "HEAD") == ""  # plain git is now blind to the commit


def test_replace_refs_do_not_blind_the_primitives(dot):
    """(2) refs/replace live in the shared ref store: change_set/stage_task/incoming must read the real objects."""
    main, wt, base = dot
    _evil_commit(wt)
    _replace_base_with_evil_tree(wt, base)
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] == 0 and cs["paths"][SWARM_MD]["in"] == ["committed", "index", "worktree"], cs
    assert run(_p.stage_task(str(wt), base))["tier_b"] == [SWARM_MD]
    assert _git(main, "rev-parse", "HEAD").strip() == base
    assert _inc(run(_p.incoming(str(main), _branch(wt)))) == {"paths": [SWARM_MD], "exit_code": 0}


def test_grafts_do_not_blind_incoming(dot):
    """(2) <common dir>/info/grafts (still honoured by git, deprecated) can make the task tip a parent of the
    mission HEAD, so HEAD...<branch> would be empty; GIT_GRAFT_FILE points the primitives away from it."""
    main, wt, base = dot
    _evil_commit(wt)
    task = _git(wt, "rev-parse", "HEAD").strip()
    _w(main / "src/m.go")
    _git(main, "add", "--", "src/m.go")
    _git(main, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "m")
    mission = _git(main, "rev-parse", "HEAD").strip()
    _w(main / ".git/info/grafts", f"{mission} {base} {task}\n")
    assert _git(main, "-c", "advice.graftFileDeprecated=false", "diff", "--name-only", f"HEAD...{task}") == ""
    assert _inc(run(_p.incoming(str(main), _branch(wt)))) == {"paths": [SWARM_MD], "exit_code": 0}
    assert run(_p.change_set(str(wt), base))["commits"] == 1


def test_maker_staged_excluded_path_is_put_back_to_head(dot):
    """(3) an excluded path the maker staged itself (`git add -f`) must not end up in the caller's commit."""
    _, wt, base = dot
    _w(wt / "@fix_plan.md", "| plan |\n")
    _git(wt, "add", "-f", "--", "@fix_plan.md")
    _w(wt / "src/new.go")
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": ["src/new.go"], "tier_b": [], "zero_diff": False, "exit_code": 0}, r
    assert _git(wt, "ls-files", "--", "@fix_plan.md") == "" and (wt / "@fix_plan.md").read_text() == "| plan |\n"


def test_maker_staged_excluded_tracked_path_index_back_to_head_worktree_kept(dot):
    _, wt, base = dot
    _w(wt / "@fix_plan.md", "v1\n")
    _git(wt, "add", "-f", "--", "@fix_plan.md")
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "plan v1")
    (wt / "@fix_plan.md").chmod(0o755)
    _w(wt / "@fix_plan.md", "v2\n")
    _git(wt, "add", "--", "@fix_plan.md")
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": [], "tier_b": [], "zero_diff": False, "exit_code": 0}, r
    assert _git(wt, "ls-files", "-s", "--", "@fix_plan.md").startswith("100644 ")  # HEAD's mode and blob
    assert _git(wt, "show", ":@fix_plan.md") == "v1\n" and (wt / "@fix_plan.md").read_text() == "v2\n"


def _nested_repo(path: Path) -> str:
    path.mkdir(parents=True)
    _git(path, "init", "-q", "-b", "main")
    _w(path / "f")
    _git(path, "add", "f")
    _git(path, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "n")
    return _git(path, "rev-parse", "HEAD").strip()


@pytest.mark.parametrize("dotgit", ["repo", "gitfile", "symlink"])
def test_untracked_nested_repo_is_refused_not_zero_diff(dot, tmp_path, dotgit):
    """(4) A nested repository (any `.git` entry below the top level) is refused by the Python working-tree scan, by change_set
    too. T6c a9 changed change_set here: it used to list it as `src/sub/` (kind gitlink); a git command reading the working tree
    would run that repository's own filters (Checker a7 finding 2)."""
    _, wt, base = dot
    if dotgit == "repo":
        _nested_repo(wt / "src/sub")
    elif dotgit == "gitfile":
        _w(wt / "src/sub/.git", f"gitdir: {tmp_path}/nowhere\n")
    else:
        (wt / "src/sub").mkdir()
        (wt / "src/sub/.git").symlink_to(tmp_path)
    for r in (run(_p.change_set(str(wt), base)), run(_p.stage_task(str(wt), base))):
        assert r["exit_code"] != 0 and "nested git repository" in r["error"] and "src/sub" in r["error"], r
        assert "paths" not in r and "zero_diff" not in r and "tree" not in r, r
    assert _index_names(wt) == ""


def test_changed_gitlink_is_refused(dot):
    _, wt, base = dot
    sha = _nested_repo(wt / "src/sub")
    _git(wt, "update-index", "--add", "--cacheinfo", f"160000,{sha},src/sub")
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "gitlink")
    _w(wt / "src/sub/f", "changed\n")
    _git(wt / "src/sub", "-c", "commit.gpgsign=false", "commit", "-q", "-am", "moved")
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "nested git repository" in r["error"], r


def test_post_stage_check_catches_a_path_update_index_did_not_stage(dot, monkeypatch):
    """(4) fail-closed backstop: every intended entry must be in the written tree. T6c a9: the old trigger (a nested repository
    update-index silently skipped, `_is_repo_dir` patched off) no longer exists, so update-index is made to drop one record."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    real = sa._git_b

    def spy(cwd, *args, stdin=None, **kw):
        if args[:1] == ("update-index",):
            stdin = b"".join(x + b"\0" for x in stdin.split(b"\0") if x and not x.endswith(b"\tsrc/new.go"))
        return real(cwd, *args, stdin=stdin, **kw)

    monkeypatch.setattr(sa, "_git_b", spy)
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "does not match the working tree" in r["error"] and "src/new.go" in r["error"], r
    assert "tree" not in r and _index_names(wt) == ""


@pytest.mark.parametrize("branch", ["", "HEAD", "@", "TAG", "SHA", "SHORT", "BRANCH~0", "refs/heads/BRANCH"])
def test_incoming_accepts_only_an_existing_local_branch(dot, branch):
    """(5) "" (change_set's detached HEAD), HEAD, @, tags, shas and revision expressions are not a task branch."""
    main, wt, _ = dot
    _evil_commit(wt)
    tip, br = _git(wt, "rev-parse", "HEAD").strip(), _branch(wt)
    _git(main, "tag", "TAG", tip)
    branch = branch.replace("BRANCH", br).replace("SHORT", tip[:12]).replace("SHA", tip)
    r = run(_p.incoming(str(main), branch))
    assert r["exit_code"] != 0 and r["error"] and "paths" not in r, r
    assert _inc(run(_p.incoming(str(main), br))) == {"paths": [SWARM_MD], "exit_code": 0}


def test_incoming_from_detached_change_set_branch_is_refused(dot):
    main, wt, base = dot
    _git(wt, "checkout", "-q", "--detach")
    br = run(_p.change_set(str(wt), base))["branch"]
    assert br == "" and run(_p.incoming(str(main), br))["exit_code"] != 0


@pytest.mark.parametrize("wt", [None, 1, "WT\0x", "WT"])
def test_tier_b_hits_bad_input_keeps_every_path_in_hits(dot, wt):
    """(6) every failure carries hits = every path-like given path (the generic boundary dict has no hits)."""
    _, real, base = dot
    wt = str(real).join(wt.split("WT")) if isinstance(wt, str) else wt
    paths = ["src/a.go", SWARM_MD] + (["bad\0path", b"src/b.go", 7] if wt == str(real) else [])
    r = run(_p.tier_b_hits(wt, paths))
    assert r["exit_code"] != 0 and r["error"], r
    assert r["hits"] == ["src/a.go", SWARM_MD] + (["bad\0path", "src/b.go"] if wt == str(real) else []), r
    for bad in (None, 3):
        assert run(_p.tier_b_hits(str(real), bad))["exit_code"] != 0
    s = run(_p.stage_task(wt, base))
    if wt != str(real):
        assert s["exit_code"] != 0 and s["error"] and "staged" not in s and "zero_diff" not in s, s


def test_stage_task_tree_is_what_the_caller_must_commit(dot):
    """(tree) the caller compares HEAD^{tree} with `tree` after its commit; an index change in between shows up."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and len(r["tree"]) == 40, r
    entries = _git(wt, "ls-files", "-s")
    assert _git(wt, "write-tree").strip() == r["tree"] and _git(wt, "ls-files", "-s") == entries
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "task")
    assert _git(wt, "rev-parse", "HEAD^{tree}").strip() == r["tree"]
    _w(wt / "src/later.go")
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0, r
    _w(wt / "src/sneaked.go")
    _git(wt, "add", "--", "src/sneaked.go")  # e.g. a background process the maker left running
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "task2")
    assert _git(wt, "rev-parse", "HEAD^{tree}").strip() != r["tree"]


# Representative paths copied from agent/scripts/test-write-scope-parity.sh (protected, non-protected, T19 sets);
# "$HOME" becomes the fake HOME. Expected values are pinned so the bash canon and the adapter cannot agree on a regression.
_PARITY_PROTECTED = [
    "/tmp/x/claude/hooks/foo.sh", "/tmp/x/agent/harnesses/claude/hooks/foo.sh", "/tmp/x/agent/hooks/claude/foo.sh",
    "/tmp/x/agent/hooks/agy/foo.sh", "/tmp/x/agent/hooks/pi/foo.ts", "/tmp/x/agent/harnesses/agy/hooks/foo.sh",
    "/tmp/x/agent/harnesses/pi/extensions/foo.ts", "/tmp/x/agent/harnesses/pi/model-routing.json",
    "/tmp/x/agent/skills/foo/SKILL.md", "/tmp/x/agent/skills/foo/scripts/bar.sh", "/tmp/x/agent/skills/foo/README.md",
    "/tmp/x/agent/SWARM.md", "/tmp/x/agent/SWARM_REFERENCES.md", "/tmp/x/claude/CLAUDE.md",
    "/tmp/x/agent/harnesses/claude/CLAUDE.md", "/tmp/x/claude/settings.json", "/tmp/x/agent/harnesses/claude/settings.json",
    "/tmp/x/claude/settings.local.json", "/tmp/x/agent/harnesses/claude/settings.local.json", "/tmp/x/agent/agents/foo.md",
    "/tmp/x/agent/write-scope-rules.json", "/tmp/x/agent/scripts/hooks/decide.py",
    "/tmp/x/agent/scripts/hooks/rule_engine.py",
    "$HOME/go/src/github.com/kpango/dotfiles/.claude/settings.json",
    "$HOME/go/src/github.com/kpango/dotfiles/.claude/worktrees/somebranch/.claude/settings.json",
    "$HOME/go/src/github.com/kpango/dotfiles/.claude/settings.local.json",
    "$HOME/go/src/github.com/kpango/dotfiles/.claude/worktrees/somebranch/.claude/settings.local.json",
    "$HOME/go/src/github.com/vdaas/vald/.claude/settings.json",
    "$HOME/go/src/github.com/vdaas/vald/.claude/worktrees/somebranch/.claude/settings.json",
    "$HOME/go/src/github.com/vdaas/vald/.claude/settings.local.json",
    "$HOME/go/src/github.com/vdaas/vald/.claude/worktrees/somebranch/.claude/settings.local.json",
    "/tmp/x/agent/scripts/jev/guard_advisor.py", "/tmp/x/agent/scripts/jev/tier_advisor.py",
    "/tmp/x/agent/scripts/jev/evidence_reducer.py", "/tmp/x/agent/scripts/jev/revision_check.py",
    "/tmp/x/agent/scripts/jev/jev_client.py", "/tmp/x/agent/scripts/jev/questions.py",
    "/tmp/x/agent/scripts/jev/calibration/calibrate.py", "/tmp/x/agent/scripts/jev/calibration/laya-calibration.json",
    "/tmp/x/dockers/laya.Dockerfile",
]
_PARITY_UNPROTECTED = [
    "/tmp/x/agent/README.md", "$HOME/project/main.go", "/tmp/x/agent/scripts/test-foo.sh",
    "$HOME/go/src/github.com/kpango/dotfiles/some/file.go", "/tmp/x/agent/agents.md",
    "/tmp/x/agent/scripts/jev/test_guard_advisor.py", "/tmp/x/agent/scripts/jev/test_tier_advisor.py",
    "/tmp/x/agent/scripts/jev/test_evidence_reducer.py", "/tmp/x/agent/scripts/jev/test_revision_check.py",
    "/tmp/x/agent/scripts/jev/test_jev_client.py", "/tmp/x/agent/scripts/jev/test_support_mock_laya.py",
    "/tmp/x/agent/scripts/jev/test_support_revision_fixture.py", "/tmp/x/agent/scripts/jev/test_security_gate_pi.ts",
    "/tmp/x/agent/scripts/jev/test_decide_integration.py", "/tmp/x/agent/scripts/jev/calibration/guard.jsonl",
    "/tmp/x/agent/scripts/jev/calibration/tier.jsonl", "/tmp/x/agent/scripts/jev/calibration/loglines.jsonl",
    "/tmp/x/agent/scripts/jev/calibration/README.md", "/tmp/x/agent/scripts/jev/calibration/test_calibration.py",
    "/tmp/x/dockers/laya-entrypoint.sh", "/tmp/x/dockers/laya-fetch-checkpoint.py",
    # prime worktree layout (CONTEXT Q8): no fixed pattern by itself, which is why tier_b_hits adds the main-checkout twin
    "$HOME/go/src/github.com/kpango/.worktrees/dotfiles/m-1/.claude/settings.json",
]


def test_tier_b_match_parity_with_write_scope_lib():
    home = os.environ["HOME"]
    paths = [p.replace("$HOME", home) for p in _PARITY_PROTECTED + _PARITY_UNPROTECTED]
    script = 'source "$1"; shift; for p in "$@"; do if write_scope_is_protected "$p"; then echo 1; else echo 0; fi; done'
    lib = REPO_AGENT / "skills/swarm-implement/scripts/write-scope-lib.sh"
    out = subprocess.run(["bash", "-c", script, "x", str(lib), *paths], capture_output=True, text=True, check=True).stdout
    bash = [line == "1" for line in out.splitlines()]
    mine = [sa._tier_b_match(_rules(), p, home) for p in paths]
    want = [True] * len(_PARITY_PROTECTED) + [False] * len(_PARITY_UNPROTECTED)
    assert len(bash) == len(paths)
    assert [p for p, b, w in zip(paths, bash, want) if b != w] == []
    assert [p for p, m, w in zip(paths, mine, want) if m != w] == []


# ---- T6c attempt 3: the returned tree is verified, the repository is pinned, one-shot inputs, merge sha ----------
def _inject_tier_b(wt) -> None:
    """What a process the maker left running does: put an agent/SWARM.md blob into the index."""
    oid = subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=wt, input="evil\n", check=True,
                         capture_output=True, text=True).stdout.strip()
    _git(wt, "update-index", "--add", "--cacheinfo", f"100644,{oid},{SWARM_MD}")


@contextlib.contextmanager
def _index_file(index: str | None):
    """The test's own plain git calls hit `index` (stage_task's private GIT_INDEX_FILE) instead of the worktree's index."""
    old = os.environ.get("GIT_INDEX_FILE")
    if index:
        os.environ["GIT_INDEX_FILE"] = index
    try:
        yield
    finally:
        if old is None:
            os.environ.pop("GIT_INDEX_FILE", None)
        else:
            os.environ["GIT_INDEX_FILE"] = old


def _on_nth_write_tree(monkeypatch, wt, n: int, inject=None) -> list:
    """Run `inject` (default `_inject_tier_b`) right before the n-th `git write-tree` of the primitives, against the index that
    write-tree reads (deterministic stand-in for a concurrent writer): the 1st is stage_task's private index (the tree it verifies),
    the 2nd the real index after `read-tree <verified tree>`."""
    real, calls = sa._pgit, []

    def spy(cwd, *args, **kw):
        if args and args[0] == "write-tree":
            calls.append(1)
            if len(calls) == n:
                with _index_file(kw.get("index")):
                    (inject or (lambda: _inject_tier_b(wt)))()
        return real(cwd, *args, **kw)

    monkeypatch.setattr(sa, "_pgit", spy)
    return calls


def test_index_write_between_check_and_write_tree_is_refused(dot, monkeypatch):
    """(1) the Tier B check ran before staging; a Tier B entry that reaches the index afterwards must not come back as `tree`."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    _on_nth_write_tree(monkeypatch, wt, 1)
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 3 and r["tier_b"] == [SWARM_MD] and "tree" not in r and r["staged"] == [], r
    assert _index_names(wt) == ""  # the real index is written only after the tree passed: untouched here


def test_real_index_write_before_the_build_is_discarded(dot, monkeypatch):
    """T6c a9: the result is built in a private index from the working tree, so an entry written to the REAL index meanwhile never
    reaches the tree, and `read-tree <tree>` replaces it."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    real = sa._pgit

    def spy(cwd, *args, **kw):
        if args[:1] == ("write-tree",) and kw.get("index"):
            _inject_tier_b(wt)  # no _index_file(): the real index
        return real(cwd, *args, **kw)

    monkeypatch.setattr(sa, "_pgit", spy)
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": ["src/new.go"], "tier_b": [], "zero_diff": False, "exit_code": 0}, r
    assert _index_names(wt) == "src/new.go\n"


def test_index_write_after_verification_is_refused(dot, monkeypatch):
    """(1) the tree that was verified must still be the index at the end (second write-tree)."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    calls = _on_nth_write_tree(monkeypatch, wt, 2)
    r = run(_p.stage_task(str(wt), base))
    assert len(calls) == 2 and r["exit_code"] != 0 and "tree" not in r and "changed while" in r["error"], r


def test_stage_task_returns_a_tree_whose_every_path_is_checked(dot):
    """(1) positive control: the verified tree is what a commit would carry (no injection -> exit 0, tree == index)."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["tree"] == _git(wt, "write-tree").strip() and r["staged"] == ["src/new.go"], r


@pytest.mark.parametrize("where", ["gitattributes", "info-attributes", "info-attributes-eq-name", "fsmonitor"])
def test_maker_filters_and_fsmonitor_never_run(dot, tmp_path, where):
    """(1) a clean filter / core.fsmonitor in the shared git dir is a command git would run inside stage_task's own
    update-index/diff (and could write the index mid-staging): no git command of the primitives reads the working tree.
    `x=y`: a driver name `-c filter.x=y.clean=` cannot blank (Checker a7 finding 1)."""
    _, wt, base = dot
    marker = tmp_path / "maker-code-ran"
    script = _w(tmp_path / "maker.sh", f"#!/bin/sh\necho ran >> {marker}\ncat\n")
    script.chmod(0o755)
    common = Path(_git(wt, "rev-parse", "--path-format=absolute", "--git-common-dir").strip())
    name = "x=y" if where.endswith("eq-name") else "fmt"
    if where == "fsmonitor":
        fsm = _w(tmp_path / "fsm.sh", f"#!/bin/sh\necho ran >> {marker}\nprintf '\\0'\n")
        fsm.chmod(0o755)
        _git(wt, "config", "core.fsmonitor", str(fsm))
    else:
        _git(wt, "config", f"filter.{name}.clean", str(script))
        _git(wt, "config", f"filter.{name}.smudge", str(script))
        if where == "gitattributes":
            _w(wt / ".gitattributes", f"*.go filter={name}\n")
        else:
            _w(common / "info/attributes", f"*.go filter={name}\n")
    _w(wt / "src/new.go")
    _w(wt / "src/a.go", "changed\n")
    cs = run(_p.change_set(str(wt), base))
    r = run(_p.stage_task(str(wt), base, exclude=(".gitattributes",)))
    assert cs["exit_code"] == 0 and r["exit_code"] == 0 and "src/new.go" in r["staged"], (cs, r)
    assert not marker.exists(), marker.read_text()


def _diverged(main) -> None:
    """main and branch `task` both change src/a.go at different lines: ort merges it as text, or through a merge driver."""
    _w(main / "src/a.go", "".join(f"{c}\n" for c in "abcdefg"))
    _commit(main, "src/a.go")
    _git(main, "checkout", "-q", "-b", "task")
    _w(main / "src/a.go", "".join(f"{c}\n" for c in "Abcdefg"))
    _commit(main, "src/a.go")
    _git(main, "checkout", "-q", "main")
    _w(main / "src/a.go", "".join(f"{c}\n" for c in "abcdefG"))
    _commit(main, "src/a.go")


@pytest.mark.parametrize("where", ["gitattributes", "info-attributes"])
def test_merge_driver_configured_after_the_check_never_runs_in_incoming(dot, tmp_path, monkeypatch, where):
    """The shadow repository (no config, no attributes) is what keeps a driver out of incoming's own merge-tree: a plain text merge,
    no child process. T6c a11: there is no up-front driver check any more (a9-a10 refused configured drivers because the caller then
    ran `git merge` in the real repository; the merge is now committed from this very merge-tree result), so "configured after the
    check" is simply "configured"."""
    main, _, _ = dot
    marker = tmp_path / "maker-code-ran"
    _diverged(main)
    _w(main / (".gitattributes" if where == "gitattributes" else ".git/info/attributes"), "* merge=x=y\n")
    _git(main, "config", "merge.x=y.driver", f"touch {marker}; cp %B %A")
    _git(main, "merge-tree", "--write-tree", "main", "task")
    assert marker.exists()  # sanity: plain git does select and run the driver
    marker.unlink()
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    r = run(_p.incoming(str(main), "task"))
    assert not marker.exists() and r["exit_code"] == 0 and r["paths"] == ["src/a.go"], r  # plain text merge, no driver
    assert _child_starts(trace) == []


def test_filter_sanity_marker_runs_for_plain_git(dot, tmp_path):
    """The marker approach above would be vacuous if git never ran the filter: plain `git update-index` does."""
    _, wt, _ = dot
    marker = tmp_path / "maker-code-ran"
    script = _w(tmp_path / "maker.sh", f"#!/bin/sh\necho ran >> {marker}\ncat\n")
    script.chmod(0o755)
    _git(wt, "config", "filter.fmt.clean", str(script))
    _w(wt / ".gitattributes", "*.go filter=fmt\n")
    _w(wt / "src/new.go")
    _git(wt, "update-index", "--add", "--", "src/new.go")
    assert marker.exists()


def _decoy_worktree(tmp_path) -> Path:
    """A worktree of an unrelated clone: what a maker points <wt>/.git at."""
    decoy = tmp_path / "decoy"
    _git(tmp_path, "init", "-q", "-b", "main", str(decoy))
    _w(decoy / "f")
    _commit(decoy, "f")
    dwt = tmp_path / "decoy-wt"
    _git(decoy, "worktree", "add", "-q", "--detach", str(dwt), "HEAD")
    return dwt


def test_gitfile_redirected_to_a_decoy_repository_is_refused(dot, tmp_path):
    """(2) a maker repoints <wt>/.git at a decoy worktree: change_set/stage_task used to answer for the decoy (empty)."""
    main, wt, base = dot
    expect = str(main / ".git")
    _w(wt / "src/new.go")
    _w(wt / SWARM_MD, "evil\n")
    (wt / ".git").write_text((_decoy_worktree(tmp_path) / ".git").read_text())
    for r in (run(sa.change_set(str(wt), base, expect_common_dir=expect)),
              run(sa.stage_task(str(wt), base, expect_common_dir=expect)),
              run(sa.tier_b_hits(str(wt), [SWARM_MD], expect_common_dir=expect)),
              run(sa.incoming(str(wt), "main", expect_common_dir=expect))):
        assert r["exit_code"] != 0 and "expected" in r["error"] and "paths" not in r and "tree" not in r, r
    assert run(sa.tier_b_hits(str(wt), [SWARM_MD], expect_common_dir=expect))["hits"] == [SWARM_MD]


def test_gitfile_redirected_to_a_sibling_worktree_of_the_same_repo_is_refused(dot, monkeypatch):
    """(2) same common dir, but another worktree's admin dir (its `gitdir` backlink names a different checkout)."""
    main, wt, base = dot
    other = run(sa.worktree_alloc("t2", cwd=str(main)))
    expect = other["common_dir"]
    assert expect == os.path.realpath(main / ".git")
    ok = run(sa.change_set(str(wt), base, expect_common_dir=expect))
    assert ok["exit_code"] == 0, ok
    (wt / ".git").write_text((Path(other["path"]) / ".git").read_text())
    for r in (run(sa.change_set(str(wt), base, expect_common_dir=expect)),
              run(sa.stage_task(str(wt), base, expect_common_dir=expect))):
        assert r["exit_code"] != 0 and "own admin dir" in r["error"] and "paths" not in r, r


def test_symlinked_dot_git_is_refused(dot, tmp_path):
    main, wt, base = dot
    expect = str(main / ".git")
    gitfile = (wt / ".git").read_text()
    real = tmp_path / "real-gitfile"
    real.write_text(gitfile)
    (wt / ".git").unlink()
    (wt / ".git").symlink_to(real)
    r = run(sa.change_set(str(wt), base, expect_common_dir=expect))
    assert r["exit_code"] != 0 and "symlink" in r["error"] and "paths" not in r, r


@pytest.mark.parametrize("bad", [None, "", "relative/.git", "/nonexistent/.git", 3])
def test_expect_common_dir_is_required_and_must_match(dot, bad):
    main, wt, base = dot
    kw = {} if bad is None else {"expect_common_dir": bad}
    for r in (run(sa.change_set(str(wt), base, **kw)), run(sa.stage_task(str(wt), base, **kw)),
              run(sa.incoming(str(wt), "main", **kw)), run(sa.tier_b_hits(str(wt), [SWARM_MD], **kw))):
        assert r["exit_code"] != 0 and r["error"] and "paths" not in r and "tree" not in r and "zero_diff" not in r, r
    th = run(sa.tier_b_hits(str(wt), [SWARM_MD, "x"], **kw))
    assert th["hits"] == [SWARM_MD, "x"]
    assert run(sa.change_set(str(wt), base, expect_common_dir=str(main / ".git")))["exit_code"] == 0


@pytest.mark.parametrize("mk", [lambda ps: (p for p in ps), lambda ps: map(str, ps), lambda ps: filter(None, ps),
                                lambda ps: iter(ps), lambda ps: tuple(ps)])
def test_tier_b_hits_one_shot_iterables_are_not_consumed_twice(dot, mk):
    """(3) generator/map/filter used to be eaten by the fail-closed fallback list and then hit nothing (fail-open)."""
    _, wt, _ = dot
    r = run(_p.tier_b_hits(str(wt), mk([SWARM_MD, "src/a.go"])))
    assert r["exit_code"] == 0 and r["hits"] == [SWARM_MD], r


def test_tier_b_hits_failure_still_reports_every_path_of_a_one_shot_iterable(dot):
    r = run(sa.tier_b_hits(dot[1].as_posix(), (p for p in [SWARM_MD, "src/a.go"]), expect_common_dir="/nonexistent/.git"))
    assert r["exit_code"] != 0 and r["hits"] == [SWARM_MD, "src/a.go"], r


@pytest.mark.parametrize("single", [SWARM_MD, SWARM_MD.encode(), Path(SWARM_MD)])
def test_tier_b_hits_single_path_instead_of_a_list_is_an_error(dot, single):
    _, wt, _ = dot
    r = run(_p.tier_b_hits(str(wt), single))
    assert r["exit_code"] != 0 and "single" in r["error"] and r["hits"] == [SWARM_MD], r


def test_incoming_returns_the_shas_it_checked(dot, monkeypatch, tmp_path):
    """(4) the merge must use `sha` (not the branch name) and only while HEAD is still `head`."""
    main, _, _ = dot
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wts"))
    mission = Path(run(sa.worktree_alloc("mission", cwd=str(main)))["path"])
    task = run(sa.worktree_alloc("task", cwd=str(mission)))
    tp = Path(task["path"])
    _w(tp / "src/t.go")
    _commit(tp, "src/t.go")
    r = run(_p.incoming(str(mission), task["branch"]))
    checked_sha, checked_head = r["sha"], r["head"]
    assert checked_sha == _git(tp, "rev-parse", "HEAD").strip() and checked_head == _git(mission, "rev-parse", "HEAD").strip()
    _evil_commit(tp)  # the branch moves after the check
    _w(mission / "src/m.go")
    _commit(mission, "src/m.go")  # and so does the mission HEAD
    assert _git(tp, "rev-parse", "HEAD").strip() != checked_sha and _git(mission, "rev-parse", "HEAD").strip() != checked_head
    # what was checked is what the returned shas name: merging them brings exactly `paths`
    assert _git(mission, "diff", "--name-only", f"{checked_head}...{checked_sha}").split() == r["paths"] == ["src/t.go"]


@pytest.mark.parametrize("staged_only", [False, True])
def test_gitlink_missing_from_the_working_tree_is_refused(dot, staged_only):
    """(minor) a gitlink without its directory was staged as a deletion of the submodule."""
    _, wt, base = dot
    sha = _nested_repo(wt / "src/sub")
    _git(wt, "update-index", "--add", "--cacheinfo", f"160000,{sha},src/sub")
    if not staged_only:
        _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "gitlink")
    shutil.rmtree(wt / "src/sub")
    head_before = _git(wt, "ls-files", "-s", "--", "src/sub")
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "gitlink absent" in r["error"] and "tree" not in r, r
    assert _git(wt, "ls-files", "-s", "--", "src/sub") == head_before  # nothing was staged for it


# ---- T6c attempt 4: gitlinks cannot be hidden, symlink blobs are resolved in the tree, merges are verified ---------
def _blob(wt, text: str) -> str:
    return subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=wt, input=text, check=True,
                          capture_output=True, text=True).stdout.strip()


def _hide_submodules(wt, how: str, path: str) -> None:
    """`.gitmodules` `ignore = all` (a working tree file) and/or `diff.ignoreSubmodules = all` (the SHARED repo config)."""
    if how in ("gitmodules", "both"):
        _w(Path(wt) / ".gitmodules", f'[submodule "evil"]\n\tpath = {path}\n\turl = x\n\tignore = all\n')
    if how in ("config", "both"):
        _git(wt, "config", "diff.ignoreSubmodules", "all")


def _plain_diff_sees(wt, *args) -> str:
    """What an UNPATCHED `git diff --name-only` shows (not the primitives' argv): proves the hiding setup really hides."""
    return _git(wt, "diff", "--name-only", *args)


@pytest.mark.parametrize("how", ["gitmodules", "config", "both"])
@pytest.mark.parametrize("committed", [False, True])
def test_hidden_gitlink_is_refused_by_stage_task(dot, how, committed):
    """A gitlink staged/committed under a non-Tier-B name with submodule diffs switched off must not come back as a `tree`."""
    _, wt, base = dot
    _git(wt, "update-index", "--add", "--cacheinfo", f"160000,{base},src/evil")
    if committed:
        _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "gitlink")
    _hide_submodules(wt, how, "src/evil")
    assert "src/evil" not in _plain_diff_sees(wt, *(("--cached",) if not committed else (base, "HEAD")))  # it IS hidden
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "gitlink" in r["error"] and "tree" not in r, r


@pytest.mark.parametrize("how", ["gitmodules", "config", "both"])
def test_hidden_gitlink_is_seen_by_change_set(dot, how):
    _, wt, base = dot
    _git(wt, "update-index", "--add", "--cacheinfo", f"160000,{base},src/evil")
    _hide_submodules(wt, how, "src/evil")
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] == 0 and cs["paths"]["src/evil"]["in"] == ["index"], cs


def test_hidden_gitlink_at_a_tier_b_path_is_a_tier_b_hit(dot):
    """The checker's e2e: a gitlink at agent/hooks/claude/evil.sh, hidden by .gitmodules + diff.ignoreSubmodules."""
    _, wt, base = dot
    _git(wt, "update-index", "--add", "--cacheinfo", f"160000,{base},agent/hooks/claude/evil.sh")
    _hide_submodules(wt, "both", "agent/hooks/claude/evil.sh")
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 3 and r["tier_b"] == ["agent/hooks/claude/evil.sh"] and "tree" not in r, r


def test_gitlink_final_check_is_independent_of_the_earlier_ones(dot, monkeypatch):
    """Even if the pre-staging layers see nothing (a gitlink injected after them), the verified tree's diff refuses it."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    _on_nth_write_tree(monkeypatch, wt, 1, lambda: _git(wt, "update-index", "--add", "--cacheinfo", f"160000,{base},src/evil"))
    _hide_submodules(wt, "both", "src/evil")
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "gitlink / submodule entries" in r["error"] and "src/evil" in r["error"] and "tree" not in r, r


@pytest.mark.parametrize("how", ["gitmodules", "config", "both"])
def test_hidden_gitlink_is_refused_by_incoming(dot, how):
    main, wt, base = dot
    _git(wt, "update-index", "--add", "--cacheinfo", f"160000,{base},src/evil")
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "gitlink")
    _hide_submodules(main, how, "src/evil")
    assert "src/evil" not in _plain_diff_sees(main, f"{base}...{_branch(wt)}")
    r = run(_p.incoming(str(main), _branch(wt)))
    assert r["exit_code"] != 0 and "gitlink" in r["error"] and "paths" not in r, r


def _inject_link(wt, path: str, target: str) -> None:
    _git(wt, "update-index", "--add", "--cacheinfo", f"120000,{_blob(wt, target)},{path}")


def _inject_on_first_write_tree(monkeypatch, inject) -> None:
    _on_nth_write_tree(monkeypatch, None, 1, inject)


@pytest.mark.parametrize("links, want", [
    ({"src/x": "../agent/SWARM.md"}, [SWARM_MD]),                                   # relative, resolved from the link's dir
    ({"src/x": "y", "src/y": "../agent/SWARM.md"}, [SWARM_MD]),                      # a chain through the tree
    ({"a/b/x": "../../agent/hooks/claude/../claude/x.sh"}, [HOOK]),                  # `..` inside the target
    ({"src/x": "/H/go/src/github.com/kpango/dotfiles/.claude/settings.json"},        # absolute, outside the repository
     [".claude/settings.json", "/H/go/src/github.com/kpango/dotfiles/.claude/settings.json"]),  # a13: + its main-checkout twin
    ({"src/x": "../" * 40 + "H/go/src/github.com/kpango/dotfiles/.claude/settings.local.json"},  # relative, climbs out (clamped at /)
     [".claude/settings.local.json", "/H/go/src/github.com/kpango/dotfiles/.claude/settings.local.json"]),
])
def test_index_injected_symlink_to_tier_b_is_a_hit(dot, monkeypatch, links, want):
    """The Tier B check reads the working tree, which an index-injected symlink blob never touches: the target is resolved
    inside the verified tree instead (and the working tree has nothing at the link's path)."""
    _, wt, base = dot
    home = os.environ["HOME"]
    links = {k: v.replace("/H/", home + "/").replace("H/go", home.lstrip("/") + "/go") for k, v in links.items()}
    want = [w.replace("/H/", home + "/") for w in want]
    _w(wt / "src/new.go")
    _inject_on_first_write_tree(monkeypatch, lambda: [_inject_link(wt, k, v) for k, v in links.items()])
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 3 and r["tier_b"] == want and "tree" not in r, r


def test_index_injected_harmless_symlink_is_not_a_hit(dot, monkeypatch):
    _, wt, base = dot
    _w(wt / "src/new.go")
    _inject_on_first_write_tree(monkeypatch, lambda: _inject_link(wt, "src/x", "a.go"))
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["staged"] == ["src/new.go", "src/x"], r


def test_symlink_loop_is_an_error_not_a_hang(dot, monkeypatch):
    _, wt, base = dot
    _w(wt / "src/new.go")
    _inject_on_first_write_tree(monkeypatch, lambda: (_inject_link(wt, "src/x", "y"), _inject_link(wt, "src/y", "x")))
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "too deep" in r["error"] and "tree" not in r, r


def _commit_link(wt, path: str, target: str) -> None:
    _inject_link(wt, path, target)
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "link")


def test_incoming_resolves_symlinks_to_tier_b(dot):
    main, wt, base = dot
    _commit_link(wt, "src/x", "../agent/SWARM.md")
    r = run(_p.incoming(str(main), _branch(wt)))
    assert _inc(r) == {"paths": [SWARM_MD, "src/x"], "exit_code": 0}
    assert run(_p.tier_b_hits(str(main), r["paths"]))["hits"] == [SWARM_MD]


@pytest.fixture
def mission(dot, monkeypatch, tmp_path):
    """(main, mission worktree, task worktree): the task branch is allocated from the mission worktree."""
    main, _, _ = dot
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wts"))
    m = Path(run(sa.worktree_alloc("mission", cwd=str(main)))["path"])
    t = run(sa.worktree_alloc("task", cwd=str(m)))
    return main, m, Path(t["path"]), t["branch"]


def _merge(m, sha, *, hooks=True) -> None:
    off = [] if hooks else ["-c", "core.hooksPath=/dev/null"]  # `merge --no-verify` only skips pre-merge-commit / commit-msg
    _git(m, "-c", "commit.gpgsign=false", *off, "merge", "--no-ff", "-q", "-m", "merge", sha)


def test_verify_merge_clean(mission):
    _, m, t, br = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    inc = run(_p.incoming(str(m), br))
    _merge(m, inc["sha"])
    r = run(_p.verify_merge(str(m), inc["head"]))
    assert r == {"paths": ["src/t.go"], "tier_b": [], "head": _git(m, "rev-parse", "HEAD").strip(), "exit_code": 0}, r


def _post_merge_hook(main, entry: str) -> None:
    """A hook in the SHARED git dir that rewrites the merge commit it was run after (measured with git 2.54: a pre-merge-commit
    hook's index change does not reach an `ort` merge commit, but a post-merge hook can replace HEAD, and --no-verify does not skip it)."""
    hook = Path(_git(main, "rev-parse", "--path-format=absolute", "--git-common-dir").strip()) / "hooks/post-merge"
    hook.parent.mkdir(exist_ok=True)
    hook.write_text(f'#!/bin/sh\nset -e\ngit update-index --add --cacheinfo "{entry}"\n'
                    'git update-ref HEAD "$(git commit-tree "$(git write-tree)" -p HEAD^1 -p HEAD^2 -m rewritten)"\n')
    hook.chmod(0o755)


@pytest.mark.parametrize("kind", ["blob", "symlink", "gitlink"])
def test_verify_merge_catches_a_hook_rewritten_merge_and_hooks_path_off_prevents_it(mission, kind):
    """The merge commit differs from what incoming() checked: verify_merge reads the committed trees. hooksPath=/dev/null
    (one of the shadow's GIT_CONFIG_COUNT settings) keeps the hook from running at all."""
    main, m, t, br = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    inc = run(_p.incoming(str(m), br))
    entry = {"blob": f"100644,{_blob(m, 'evil' + chr(10))},{SWARM_MD}", "symlink": f"120000,{_blob(m, '../agent/SWARM.md')},src/x",
             "gitlink": f"160000,{inc['head']},src/evil"}[kind]
    _post_merge_hook(main, entry)
    _hide_submodules(m, "both", "src/evil")
    _merge(m, inc["sha"], hooks=False)
    clean = run(_p.verify_merge(str(m), inc["head"]))
    assert clean["exit_code"] == 0 and clean["paths"] == ["src/t.go"], clean
    _git(m, "reset", "-q", "--hard", inc["head"])  # the test's own undo (the adapter never does this)
    _merge(m, inc["sha"])  # the hook runs and amends the merge commit
    r = run(_p.verify_merge(str(m), inc["head"]))
    if kind == "gitlink":
        assert r["exit_code"] == 1 and "gitlink" in r["error"] and "src/evil" in r["error"], r
    else:
        assert r["exit_code"] == 3 and r["tier_b"] == [SWARM_MD] and "src/t.go" in r["paths"], r


def test_verify_merge_is_read_only(mission):
    main, m, t, br = mission
    _post_merge_hook(main, f"100644,{_blob(m, 'evil' + chr(10))},{SWARM_MD}")
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    inc = run(_p.incoming(str(m), br))
    _merge(m, inc["sha"])
    state = (_git(m, "rev-parse", "HEAD"), _git(m, "status", "--porcelain"), _git(m, "ls-files", "-s"))
    assert run(_p.verify_merge(str(m), inc["head"]))["exit_code"] == 3
    assert (_git(m, "rev-parse", "HEAD"), _git(m, "status", "--porcelain"), _git(m, "ls-files", "-s")) == state


@pytest.mark.parametrize("bad", ["", "abc1234", "HEAD", "g" * 40, None, 5])
def test_verify_merge_head_must_be_a_full_hex_sha(mission, bad):
    _, m, _, _ = mission
    r = run(_p.verify_merge(str(m), bad))
    assert r["exit_code"] != 0 and r["error"] and "paths" not in r, r


def test_verify_merge_head_must_be_an_ancestor(mission):
    _, m, t, _ = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    r = run(_p.verify_merge(str(m), _git(t, "rev-parse", "HEAD").strip()))  # the task tip is not below the mission HEAD
    assert r["exit_code"] == 1 and "not a descendant" in r["error"], r


def test_verify_merge_pins_the_repository(mission):
    _, m, _, _ = mission
    r = run(sa.verify_merge(str(m), _git(m, "rev-parse", "HEAD").strip(), expect_common_dir="/nonexistent/.git"))
    assert r["exit_code"] != 0 and r["error"], r


# ---- T6c attempt 5: incoming checks the merge RESULT, bytes symlink targets, `git rm --cached`, surviving mutants ----
def _gat(cwd, n: int, *a) -> str:
    """git with a fixed, increasing commit date: the merge-base order of a criss-cross history is then deterministic."""
    d = f"2026-01-01T00:00:{n:02d}"
    return subprocess.run(["git", *a], cwd=cwd, check=True, capture_output=True, text=True,
                          env={**os.environ, "GIT_AUTHOR_DATE": d, "GIT_COMMITTER_DATE": d}).stdout


def _criss_cross(main) -> None:
    """mission = merge(mb1, mb2) where mb2 changed HOOK; task = merge(mb2, mb1) that puts HOOK back to the base content, plus a
    commit. mission and task have TWO merge bases (mb1, mb2): `git diff mission...task` takes the first (mb1, the later one)
    and never sees HOOK, while `git merge task` (ort, virtual base) changes HOOK on the mission."""
    orig = (main / HOOK).read_text()
    _gat(main, 1, "checkout", "-q", "-b", "mb2")
    _w(main / HOOK, "O\n")
    _gat(main, 2, "commit", "-qam", "mb2")
    _gat(main, 3, "checkout", "-q", "-b", "mb1", "main")
    _w(main / "src/a.go", "1\n")
    _gat(main, 4, "commit", "-qam", "mb1")
    _gat(main, 5, "checkout", "-q", "-b", "mission", "mb1")
    _gat(main, 6, "merge", "-q", "--no-ff", "-m", "headmerge", "mb2")
    _gat(main, 7, "checkout", "-q", "-b", "task", "mb2")
    _gat(main, 8, "merge", "-q", "--no-ff", "--no-commit", "mb1")
    _w(main / HOOK, orig)
    _gat(main, 9, "add", "--", HOOK)
    _gat(main, 10, "commit", "-qm", "taskmerge")
    _w(main / "src/old.go", "2\n")
    _gat(main, 11, "commit", "-qam", "task2")
    _gat(main, 12, "checkout", "-q", "mission")


def test_incoming_checks_the_merge_result_not_a_three_dot_diff(dot):
    """(1) several merge bases: the three-dot diff used the first one only (fail-open); the ort merge result is what is checked."""
    main, _, _ = dot
    _criss_cross(main)
    assert len(_git(main, "merge-base", "--all", "mission", "task").split()) == 2
    assert _git(main, "diff", "--name-only", "mission...task").split() == ["src/old.go"]  # the old method: blind to HOOK
    inc = run(_p.incoming(str(main), "task"))
    assert inc["exit_code"] == 0 and inc["paths"] == [HOOK, "src/old.go"], inc
    assert run(_p.tier_b_hits(str(main), inc["paths"]))["hits"] == [HOOK]
    _merge(main, inc["sha"], hooks=False)
    assert (main / HOOK).read_text() == HOOK + "\n"  # the real merge did change HOOK
    assert _git(main, "rev-parse", "HEAD^{tree}").strip() == inc["tree"]  # the check the caller makes after merging
    vm = run(_p.verify_merge(str(main), inc["head"]))
    assert vm["exit_code"] == 3 and vm["tier_b"] == [HOOK] and vm["paths"] == inc["paths"], vm


def test_incoming_tree_is_the_tree_of_the_merge_commit(mission):
    _, m, t, br = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    _w(m / "src/m.go")
    _commit(m, "src/m.go")  # both sides moved: a real three-way merge
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and inc["paths"] == ["src/t.go"], inc
    _merge(m, inc["sha"])
    assert _git(m, "rev-parse", "HEAD^{tree}").strip() == inc["tree"]


def test_incoming_conflicting_merge_is_an_error(dot):
    main, wt, _ = dot
    _w(wt / "src/a.go", "task\n")
    _commit(wt, "src/a.go")
    _w(main / "src/a.go", "mission\n")
    _commit(main, "src/a.go")
    r = run(_p.incoming(str(main), _branch(wt)))
    assert r["exit_code"] != 0 and "conflict" in r["error"] and "paths" not in r and "tree" not in r, r


def test_incoming_unrelated_history_is_an_error(dot):
    main, _, _ = dot
    _git(main, "update-ref", "refs/heads/orphan", _git(main, "commit-tree", "HEAD^{tree}", "-m", "orphan").strip())
    r = run(_p.incoming(str(main), "orphan"))
    assert r["exit_code"] != 0 and "paths" not in r and "tree" not in r, r


def _child_starts(trace: Path) -> list[dict]:
    return [e for e in map(json.loads, trace.read_text().splitlines()) if e["event"] == "child_start"] if trace.exists() else []


@pytest.mark.parametrize("name", ["evil", "x=y"])
def test_maker_merge_driver_never_runs_in_incoming(dot, tmp_path, monkeypatch, name):
    """A merge driver chosen by <common dir>/info/attributes is a command `git merge-tree` runs; GIT_ATTR_SOURCE does not stop it.
    `x=y`: Checker a7 finding 1 (`-c merge.x=y.driver=` leaves it set; GIT_CONFIG_KEY_n blanks it)."""
    main, _, _ = dot
    marker = tmp_path / "maker-code-ran"
    _diverged(main)
    _w(main / ".git/info/attributes", f"* merge={name}\n")
    _git(main, "config", f"merge.{name}.driver", f"touch {marker}; cp %B %A")
    _git(main, "merge-tree", "--write-tree", "main", "task")
    assert marker.exists()  # sanity: plain git does run the driver here (so the assertion below is not vacuous)
    marker.unlink()
    old = subprocess.run(["git", "-c", f"merge.{name}.driver=", "merge-tree", "--write-tree", "main", "task"], cwd=main,
                         env={**os.environ, **sa._NO_DISTORT_ENV},
                         capture_output=True, check=False)  # the a7 blanking (`-c`), negative control
    assert marker.exists() == (name == "x=y"), old
    marker.unlink(missing_ok=True)
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    r = run(_p.incoming(str(main), "task"))
    assert not marker.exists(), marker.read_text()
    # T6c a11: no longer refused up front (a9-a10 did, since the caller ran `git merge` in the real repository; the merge is now
    # committed from this merge-tree result, in the shadow): the plain text merge, no child process.
    assert r["exit_code"] == 0 and r["paths"] == ["src/a.go"], r
    assert _child_starts(trace) == []


def _blob_b(wt, data: bytes) -> str:
    return subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=wt, input=data, check=True,
                          capture_output=True).stdout.decode().strip()


def test_symlink_target_with_a_non_utf8_name_resolves_like_its_tree_entry(dot):
    """(2) the target text is read as bytes and fs-decoded like the `links` keys: 0xff stays U+DCFF (it used to become U+FFFD)."""
    main, wt, _ = dot
    bad = os.fsdecode(b"src/bad\xff")
    _git(main, "update-index", "--add", "--cacheinfo", f"120000,{_blob(main, '../agent/SWARM.md')},{bad}")
    _git(main, "commit", "-q", "-m", "link with a non-UTF-8 name")
    _git(wt, "update-index", "--add", "--cacheinfo", f"120000,{_blob_b(wt, b'bad' + bytes([255]))},src/L")
    _git(wt, "commit", "-q", "-m", "link to it")
    r = run(_p.incoming(str(main), _branch(wt)))
    assert r["exit_code"] == 0 and r["paths"] == sorted([SWARM_MD, "src/L"]), r
    assert run(_p.tier_b_hits(str(main), r["paths"]))["hits"] == [SWARM_MD]


@pytest.mark.parametrize("content, want", [("changed\n", ["src/a.go"]), ("src/a.go\n", [])])
def test_untracking_then_keeping_the_file_stages_it_instead_of_failing(dot, content, want):
    """(3) HEAD has it, the index has not (`git rm --cached`), the working tree does: a change to stage (it was "not staged" -> exit 1)."""
    _, wt, base = dot
    _git(wt, "rm", "-q", "--cached", "--", "src/a.go")
    _w(wt / "src/a.go", content)
    assert run(_p.change_set(str(wt), base))["paths"]["src/a.go"]["kind"] == "file"
    r = run(_p.stage_task(str(wt), base))
    assert _nt(r, wt) == {"staged": want, "tier_b": [], "zero_diff": not want, "exit_code": 0}, r
    assert _git(wt, "show", ":src/a.go") == content


def test_paths_beyond_a_symlinked_directory_are_deleted_even_if_the_link_target_has_the_same_names(dot, tmp_path):
    """`_kind`: git treats src/a.go as absent (beyond the new symlink `src`) although the file system finds one through it."""
    _, wt, base = dot
    other = tmp_path / "other"
    _w(other / "a.go")
    _w(other / "old.go")
    shutil.rmtree(wt / "src")
    (wt / "src").symlink_to(other)
    assert (wt / "src/a.go").exists()
    cs = run(_p.change_set(str(wt), base))
    assert {p: v["kind"] for p, v in cs["paths"].items()} == {"src": "symlink", "src/a.go": "deleted", "src/old.go": "deleted"}, cs
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and sorted(r["staged"]) == ["src", "src/a.go", "src/old.go"], r


@pytest.mark.parametrize("kind", ["branch", "tag"])
def test_any_ref_named_like_the_base_is_refused_even_when_it_points_at_the_base_itself(dot, kind):
    """`_resolve_base`'s ref-name check is not redundant with the prefix check: a ref that git resolves to the base commit itself
    passes the prefix check (it could only fail it for a prefix collision, which cannot be built here), yet git's ref-first
    DWIM order makes any such name a way to move the base later, so it is refused."""
    _, wt, base = dot
    short = base[:12]
    _git(wt, kind, short, base)
    assert _git(wt, "rev-parse", f"{short}^{{commit}}").strip() == base
    with _opened(wt) as r:
        sha, err = sa._resolve_base(r, short)
    assert sha is None and "ambiguous with a ref name" in err["error"], (sha, err)
    assert run(_p.stage_task(str(wt), short))["exit_code"] != 0


def _decoy_gitfile(tmp_path) -> str:
    return (_decoy_worktree(tmp_path) / ".git").read_text()


def test_stage_task_pins_the_repository_again_at_the_very_end(dot, tmp_path, monkeypatch):
    """The gitfile is repointed at a decoy after the last pin inside the call but before it returns: only the final pin sees it."""
    main, wt, base = dot
    decoy = _decoy_gitfile(tmp_path)
    _w(wt / "src/new.go")
    real = sa._git_z

    def spy(cwd, *args):
        out = real(cwd, *args)
        if args[0] == "diff-tree" and "--name-only" in args:  # the last git call of stage_task
            (wt / ".git").write_text(decoy)
        return out

    monkeypatch.setattr(sa, "_git_z", spy)
    r = run(sa.stage_task(str(wt), base, expect_common_dir=str(main / ".git")))
    assert r["exit_code"] != 0 and "expected" in r["error"] and "tree" not in r, r


def test_verify_merge_pins_the_repository_again_at_the_end(mission, tmp_path, monkeypatch):
    main, m, t, br = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    inc = run(_p.incoming(str(m), br))
    _merge(m, inc["sha"])
    decoy = _decoy_gitfile(tmp_path)
    real = sa._tier_b_hits

    def spy(*a):
        out = real(*a)
        (m / ".git").write_text(decoy)  # after the Tier B check's own pin, before verify_merge returns
        return out

    monkeypatch.setattr(sa, "_tier_b_hits", spy)
    r = run(sa.verify_merge(str(m), inc["head"], expect_common_dir=str(main / ".git")))
    assert r["exit_code"] != 0 and "expected" in r["error"] and "paths" not in r, r


def test_excluded_path_injected_after_the_pre_checks_is_refused_from_the_verified_tree(dot, monkeypatch):
    """The excluded-path check on the verified tree (not on the inputs): an excluded path written to the index at write-tree time."""
    _, wt, base = dot
    _w(wt / "src/new.go")
    _inject_on_first_write_tree(monkeypatch, lambda: _git(wt, "update-index", "--add", "--cacheinfo",
                                                           f"100644,{_blob(wt, 'plan' + chr(10))},@fix_plan.md"))
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "excluded but staged" in r["error"] and "tree" not in r, r


@pytest.mark.parametrize("step", ["ls-tree", "ls-files", "check-ignore", "hash-object", "update-index", "write-tree", "read-tree"])
def test_a_failing_git_step_is_an_error_and_leaves_the_real_index_alone(dot, monkeypatch, step):
    """T6c a9 (replaces the two `_index_to_head` failure tests: excluded paths now take HEAD's entry straight from `ls-tree HEAD`).
    Any failing git step is an error with no `tree`; before `read-tree` the real index is exactly as the maker left it."""
    _, wt, base = dot
    _w(wt / "@fix_plan.md", "v1\n")
    _git(wt, "add", "-f", "--", "@fix_plan.md")  # a maker-staged excluded path: the real index differs from HEAD
    _w(wt / "src/new.go")
    before = _git(wt, "ls-files", "-s")
    rb, rp = sa._git_b, sa._pgit
    monkeypatch.setattr(sa, "_git_b", lambda cwd, *a, **k: subprocess.CompletedProcess(a, 128, b"", b"boom") if a[0] == step
                        else rb(cwd, *a, **k))
    monkeypatch.setattr(sa, "_pgit", lambda cwd, *a, **k: {"exit_code": 1, "stdout": "", "stderr": "boom"} if a[0] == step
                        else rp(cwd, *a, **k))
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "boom" in r["error"] and "tree" not in r and "zero_diff" not in r, r
    if step != "read-tree":
        assert _git(wt, "ls-files", "-s") == before


def test_committed_symlink_replaced_by_a_directory_is_staged_as_delete_plus_contents(dot):
    """`git diff HEAD` calls the link D while a directory stands there: it must be force-removed before its contents are added."""
    _, wt, base = dot
    _commit_link(wt, "src/l", "a.go")
    _w(wt / "src/l/f.go")
    assert _git(wt, "diff", "--name-status", "HEAD").split() == ["D", "src/l"]
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["staged"] == ["src/l", "src/l/f.go"], r  # HEAD..tree: the link is gone, the file is new
    assert _git(wt, "ls-files", "--", "src/l") == "src/l/f.go\n"


# ---- T6c attempt 6: derived object caches (commit-graph, multi-pack-index) -----------------------------------
def _common_dir(wt) -> Path:
    return Path(_git(wt, "rev-parse", "--path-format=absolute", "--git-common-dir").strip())


def _chunks(b: bytearray) -> dict[bytes, int]:
    """chunk id -> file offset. commit-graph: 8-byte header; multi-pack-index: 12 (extra base-file/pack counts). Then 12 bytes/chunk."""
    start = 12 if b[:4] == b"MIDX" else 8
    return {bytes(b[o:o + 4]): int.from_bytes(b[o + 4:o + 12], "big") for o in (start + i * 12 for i in range(b[6] + 1))}


def _rehash(b: bytearray, f: Path) -> None:
    b[-20:] = hashlib.sha1(bytes(b[:-20])).digest()  # the trailing checksum is all git verifies on load
    f.chmod(0o644)
    f.write_bytes(bytes(b))


def _forge_commit_graph_tree(wt, commit: str, tree: str) -> None:
    """`git commit-graph write`, then rewrite `commit`'s root tree id in the CDAT chunk (36 bytes/commit: tree, 2 parents, ...)."""
    _git(wt, "commit-graph", "write", "--reachable")
    f = _common_dir(wt) / "objects/info/commit-graph"
    b = bytearray(f.read_bytes())
    assert b[:4] == b"CGPH"
    ch = _chunks(b)
    oidl, cdat = ch[b"OIDL"], ch[b"CDAT"]
    oids = [bytes(b[o:o + 20]) for o in range(oidl, cdat, 20)]
    i = oids.index(bytes.fromhex(commit))
    b[cdat + i * 36:cdat + i * 36 + 20] = bytes.fromhex(tree)
    _rehash(b, f)


def _forge_midx_entry(wt, victim: str, donor: str) -> None:
    """`git multi-pack-index write`, then point `victim`'s OOFF entry (pack id + offset) at `donor`'s object."""
    _git(wt, "multi-pack-index", "write")
    f = _common_dir(wt) / "objects/pack/multi-pack-index"
    b = bytearray(f.read_bytes())
    assert b[:4] == b"MIDX"
    ch = _chunks(b)
    oidl, ooff = ch[b"OIDL"], ch[b"OOFF"]
    oids = [bytes(b[o:o + 20]) for o in range(oidl, ooff, 20)]
    iv, idn = oids.index(bytes.fromhex(victim)), oids.index(bytes.fromhex(donor))
    b[ooff + iv * 8:ooff + iv * 8 + 8] = bytes(b[ooff + idn * 8:ooff + idn * 8 + 8])
    _rehash(b, f)


def _config_without(monkeypatch, key: str) -> None:
    """Run the primitives without one _NO_DISTORT_CONFIG pair: the negative control that proves the forgery itself works."""
    pairs = tuple(p for p in sa._NO_DISTORT_CONFIG if p[0] != key)
    assert len(pairs) == len(sa._NO_DISTORT_CONFIG) - 1, key
    monkeypatch.setattr(sa, "_NO_DISTORT_CONFIG", pairs)


def _unshadowed(monkeypatch, drop_env=(), drop_config=()) -> None:
    """Negative control of the shadow (T6c a11): the primitives' own git commands, run against the REAL repository (GIT_DIR = the
    checkout's git dir: its config, hooks, info/*; GIT_OBJECT_DIRECTORY unset), minus the named env vars / GIT_CONFIG_COUNT pairs."""
    real = sa._senv

    def env(r, index=None, work=False):
        e = real(r, index, work)
        e["GIT_DIR"] = r.gitdir
        del e["GIT_OBJECT_DIRECTORY"]
        for k in drop_env:
            del e[k]
        n = int(e.pop("GIT_CONFIG_COUNT"))
        pairs = [(e.pop(f"GIT_CONFIG_KEY_{i}"), e.pop(f"GIT_CONFIG_VALUE_{i}")) for i in range(n)]
        pairs = [(k, v) for k, v in pairs if k not in drop_config]
        e["GIT_CONFIG_COUNT"] = str(len(pairs))
        for i, (k, v) in enumerate(pairs):
            e[f"GIT_CONFIG_KEY_{i}"], e[f"GIT_CONFIG_VALUE_{i}"] = k, v
        return e

    monkeypatch.setattr(sa, "_senv", env)


def _assert_tier_b_seen(wt, base) -> None:
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] == 0 and SWARM_MD in cs["paths"], cs
    assert run(_p.tier_b_hits(str(wt), list(cs["paths"]), expect_common_dir=_common_dir(wt)))["hits"] == [SWARM_MD]
    assert run(_p.stage_task(str(wt), base))["tier_b"] == [SWARM_MD]


def test_forged_commit_graph_does_not_blind_the_primitives(dot, monkeypatch):
    """A maker (linked worktree, shared object dir) writes objects/info/commit-graph claiming the base commit's tree is the
    tip's tree: porcelain `git diff <base>` then reports nothing for a Tier B commit. core.commitGraph=false must beat it."""
    _, wt, base = dot
    _evil_commit(wt)
    _forge_commit_graph_tree(wt, base, _git(wt, "rev-parse", "HEAD^{tree}").strip())
    assert _git(wt, "diff", "--name-only", base, "HEAD") == ""  # plain git is blind (and so would the adapter be)
    assert _git(wt, "-c", "core.commitGraph=false", "diff", "--name-only", base, "HEAD") == SWARM_MD + "\n"
    _assert_tier_b_seen(wt, base)


def test_forged_commit_graph_without_the_option_still_reads_the_real_trees(dot, monkeypatch):
    """T6c a9 (was the negative control "without core.commitGraph=false change_set reports no path"): the base/HEAD sides now come
    from `ls-tree` and `diff-tree`, which parse the commit object itself, so even WITHOUT the option this tree-id forgery does not
    blind them (measured, git 2.54), while porcelain `git diff` stays blind (asserted in the test above). The option stays as
    hardening for whatever else reads the graph (parents/generations: merge-base, rev-list)."""
    _, wt, base = dot
    _evil_commit(wt)
    _forge_commit_graph_tree(wt, base, _git(wt, "rev-parse", "HEAD^{tree}").strip())
    assert _git(wt, "diff", "--name-only", base, "HEAD") == ""
    _config_without(monkeypatch, "core.commitGraph")
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] == 0 and cs["paths"][SWARM_MD]["in"] == ["committed", "index", "worktree"], cs
    with _opened(wt) as r:
        assert [p for *_, p in sa._raw(r, "diff-tree", base, _git(wt, "rev-parse", "HEAD").strip())[0]] == [SWARM_MD]


def test_forged_multi_pack_index_does_not_blind_the_primitives(dot):
    """A forged multi-pack-index makes the base commit's root tree oid read the tip's root tree (objects read by diff are not
    hash-verified; the base commit itself is, by rev-parse --verify): same blindness, same fix."""
    _, wt, base = dot
    _evil_commit(wt)
    _git(wt, "repack", "-q", "-a", "-d")
    _forge_midx_entry(wt, _git(wt, "rev-parse", f"{base}^{{tree}}").strip(), _git(wt, "rev-parse", "HEAD^{tree}").strip())
    assert _git(wt, "diff", "--name-only", base, "HEAD") == ""
    assert _git(wt, "-c", "core.multiPackIndex=false", "diff", "--name-only", base, "HEAD") == SWARM_MD + "\n"
    _assert_tier_b_seen(wt, base)


def test_forged_multi_pack_index_without_the_option_fails_closed(dot, monkeypatch):
    """Measured on git 2.54: with the option removed, the forged midx is caught by git's own hash check in the index diff
    (change_set errors, never an empty set). The option is what makes the primitives read the real objects instead.
    T6c a17: the adapter's own re-hash of the base tree (`_verify_objects`) now catches it first, before any listing."""
    _, wt, base = dot
    _evil_commit(wt)
    _git(wt, "repack", "-q", "-a", "-d")
    _forge_midx_entry(wt, _git(wt, "rev-parse", f"{base}^{{tree}}").strip(), _git(wt, "rev-parse", "HEAD^{tree}").strip())
    _config_without(monkeypatch, "core.multiPackIndex")
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] != 0 and "object store forged" in cs["error"] and "paths" not in cs, cs
    monkeypatch.setattr(sa, "_verify_objects", lambda *a, **k: "")  # without the re-hash: git's own check, as measured before
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] != 0 and "hash mismatch" in cs["error"] and "paths" not in cs, cs


# Commands the primitives run in the shadow repository (T6c a11; `version` = the one-time git version check).
_SHADOW_CMDS = {"version", "rev-parse", "ls-tree", "ls-files", "rev-list", "merge-base", "diff-tree", "cat-file", "merge-tree",
                "check-ignore", "hash-object", "update-index", "write-tree", "read-tree", "commit-tree"}


def test_every_git_call_of_the_primitives_runs_in_the_shadow_repository(dot, monkeypatch):
    """T6c a11 structural pin (was a9's "no git call reads the working tree and all carry the settings"). Every git command of the
    seven functions: argv `git <cmd> ...` (no -C, no -c, no ref name: shas only); GIT_DIR = <mkdtemp swarm-adapter-*>/shadow.git
    holding exactly HEAD, the adapter's own config, info/exclude, objects/, refs/ (no hooks, no info/attributes); cwd = that mkdtemp
    dir, or the worktree top with GIT_WORK_TREE for check-ignore / read-tree -m -u only; GIT_OBJECT_DIRECTORY = the real objects;
    GIT_INDEX_FILE = the checkout's real index or a private `index` in the mkdtemp dir (update-index only ever the private one);
    HOME = XDG_CONFIG_HOME = <mkdtemp>/home; every _NO_DISTORT_ENV entry and _NO_DISTORT_CONFIG pair; no other GIT_* than
    GIT_TRACE*/GIT_AUTHOR_*/GIT_COMMITTER_* (inherited GIT_CONFIG_PARAMETERS, GIT_EXEC_PATH, GIT_ALTERNATE_OBJECT_DIRECTORIES, ...
    dropped). The objects the shadow writes are then in the real repository (plain git reads them)."""
    main, wt, base = dot
    _w(wt / "src/c.go")
    _commit(wt, "src/c.go")
    _w(wt / "src/n.go")
    _w(wt / "src/a.go", "changed\n")
    m = Path(run(sa.worktree_alloc("m", cwd=str(main)))["path"])  # a second swarm-prime checkout: the merge target
    kw, branch = _Pinned._kw(wt), _branch(wt)
    indexes = {os.path.realpath(_git(x, "rev-parse", "--absolute-git-dir").strip()) + "/index" for x in (wt, m)}
    objects = os.path.realpath(main / ".git") + "/objects"
    for k, v in (("GIT_CONFIG_PARAMETERS", "'core.hooksPath'='/nonexistent-inherited'"), ("GIT_CONFIG_COUNT", "1"),
                 ("GIT_CONFIG_KEY_0", "core.fsmonitor"), ("GIT_CONFIG_VALUE_0", "/nonexistent-inherited"), ("GIT_CONFIG", os.devnull),
                 ("GIT_EXEC_PATH", "/nonexistent-inherited"), ("GIT_ALTERNATE_OBJECT_DIRECTORIES", "/nonexistent-inherited"),
                 ("GIT_SHALLOW_FILE", "/nonexistent-inherited"), ("GIT_REPLACE_REF_BASE", "refs/nonexistent-inherited/")):
        monkeypatch.setenv(k, v)
    monkeypatch.setattr(sa, "_GIT_VERSION", [])  # the version check runs (and is checked) here too
    seen, real = [], subprocess.Popen  # subprocess.run goes through Popen too (T6c a17: `_cat` streams `cat-file --batch`)

    def spy(argv, *a, **k):
        if argv[0] == sa._git_exe():  # T6c a12: the absolute path resolved once (never a bare "git" looked up on PATH)
            sh = Path(k["env"]["GIT_DIR"])
            seen.append((list(argv), k.get("cwd"), dict(k["env"]), sorted(str(x.relative_to(sh)) for x in sh.rglob("*")),
                         (sh / "config").read_text()))
        return real(argv, *a, **k)

    monkeypatch.setattr(sa.subprocess, "Popen", spy)
    assert run(sa.change_set(str(wt), base, **kw))["exit_code"] == 0
    st = run(sa.stage_task(str(wt), base, **kw))
    assert st["exit_code"] == 0 and run(sa.tier_b_hits(str(wt), ["src/a.go"], **kw))["exit_code"] == 0, st
    c = run(sa.commit_tree(str(wt), st["tree"], [st["head"]], "t", **kw))
    assert run(sa.update_ref(str(wt), c["commit"], st["head"], **kw))["exit_code"] == 0, c
    inc = run(sa.incoming(str(m), branch, **kw))
    mc = run(sa.commit_tree(str(m), inc["tree"], [inc["head"], inc["sha"]], "m", **kw))
    assert run(sa.update_ref(str(m), mc["commit"], inc["head"], checkout=True, **kw))["exit_code"] == 0, (inc, mc)
    assert run(sa.verify_merge(str(m), inc["head"], **kw))["exit_code"] == 0
    monkeypatch.setattr(sa.subprocess, "Popen", real)
    for k in ("GIT_EXEC_PATH", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_SHALLOW_FILE", "GIT_REPLACE_REF_BASE", "GIT_CONFIG_PARAMETERS",
              "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_CONFIG"):
        monkeypatch.delenv(k)
    cmds, own = set(), {"GIT_DIR", "GIT_OBJECT_DIRECTORY", "GIT_INDEX_FILE", "GIT_WORK_TREE", "GIT_CONFIG_COUNT", *sa._NO_DISTORT_ENV}
    for argv, cwd, env, files, config in seen:
        sub, rest = argv[1], argv[2:]
        assert "-C" not in argv and "-c" not in argv and sub in _SHADOW_CMDS and not any("HEAD" in x for x in rest), argv
        cmds.add(sub)
        tmp = os.path.dirname(env["GIT_DIR"])
        assert os.path.basename(env["GIT_DIR"]) == "shadow.git" and os.path.basename(tmp).startswith("swarm-adapter-"), argv
        assert files == ["HEAD", "config", "info", "info/exclude", "objects", "refs"] and config == sa._SHADOW_CONFIG, (argv, files)
        assert env["GIT_OBJECT_DIRECTORY"] == objects and env["HOME"] == env["XDG_CONFIG_HOME"] == tmp + "/home", argv
        assert sa._NO_DISTORT_ENV.items() <= env.items(), argv
        got = [(env[f"GIT_CONFIG_KEY_{i}"], env[f"GIT_CONFIG_VALUE_{i}"]) for i in range(int(env["GIT_CONFIG_COUNT"]))]
        assert got == list(sa._NO_DISTORT_CONFIG), argv
        assert [x for x in env if x.startswith("GIT_") and x not in own and not x.startswith(
            ("GIT_TRACE", "GIT_AUTHOR_", "GIT_COMMITTER_", "GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))] == [], argv
        private = env["GIT_INDEX_FILE"] == tmp + "/index"
        assert private or env["GIT_INDEX_FILE"] in indexes, argv
        work = env.get("GIT_WORK_TREE")
        assert os.path.isabs(argv[0]) and cwd == tmp, argv  # T6c a12: never the working tree, also with GIT_WORK_TREE
        assert not work or (sub in ("check-ignore", "read-tree") and work in (str(wt), str(m))), argv
        shape = {"ls-files": ["-s", "-t", "-z"], "update-index": ["-z", "--index-info"], "hash-object": ["-w", "--no-filters", "--stdin-paths"],
                 "check-ignore": ["--no-index", "--stdin", "-z"], "write-tree": [], "version": []}
        if sub in shape:
            assert rest == shape[sub], argv
        assert (sub == "update-index") <= private, argv  # update-index only ever writes the private index
        if sub == "read-tree":  # the verified tree into the real index, or the merge checkout (two shas, -m -u, the working tree)
            assert not private and (rest[:2] == ["-m", "-u"] and len(rest) == 4 and work or len(rest) == 1 and not work), argv
            assert all(re.fullmatch(r"[0-9a-f]{40}", x) for x in rest if not x.startswith("-")), argv
        if sub in ("merge-tree", "commit-tree"):
            assert all(re.fullmatch(r"[0-9a-f]{40}", x) for x in rest if x not in ("--write-tree", "-z", "--no-messages", "-p", "-m",
                                                                               "t", "m")), argv
    assert cmds == _SHADOW_CMDS and ["cat-file", "--batch"] in [argv[1:] for argv, *_ in seen], cmds
    for obj, typ in ((st["tree"], "tree"), (c["commit"], "commit"), (inc["tree"], "tree"), (mc["commit"], "commit")):
        assert _git(main, "cat-file", "-t", obj).strip() == typ  # written by the shadow, in the real object store
    assert _git(wt, "rev-parse", "HEAD").strip() == c["commit"] and _git(m, "rev-parse", "HEAD").strip() == mc["commit"]
    assert (m / "src/c.go").exists() and _git(m, "status", "--porcelain") == ""  # the merge checkout updated index + working tree


@pytest.mark.parametrize("exclude", ["@fix_plan.md", ("@fix_plan.md",), ["@fix_plan.md"]])
def test_stage_task_exclude_str_is_one_path_not_its_characters(dot, exclude):
    """A bare str is ONE excluded path (like verify's str command). Iterating it would exclude the single characters
    '@', 'f', 'i', ... and stage the plan file."""
    _, wt, base = dot
    _w(wt / "@fix_plan.md", "| plan |\n")
    _w(wt / "src/new.go")
    r = run(_p.stage_task(str(wt), base, exclude=exclude))
    assert r["staged"] == ["src/new.go"] and r["exit_code"] == 0, r
    assert "@fix_plan.md" not in _git(wt, "diff", "--cached", "--name-only")


# ---- hooks of the shared git dir must not run inside the primitives (core.hooksPath=/dev/null) --------------------------
def _install_post_index_change(main, body: str) -> Path:
    """<common dir>/hooks/post-index-change: shared by every worktree, so a maker can write it. Logs each run, then runs `body`
    (sh) with $N = the 1-based run number; the hook's own git calls inherit _HOOK_BUSY and do not recurse into it."""
    log = main.parent / "hook.log"
    hook = main / ".git/hooks/post-index-change"
    hook.parent.mkdir(exist_ok=True)
    hook.write_text(f"""#!/bin/sh
[ -n "$_HOOK_BUSY" ] && exit 0
export _HOOK_BUSY=1
echo "$@" >> "{log}"
N=$(wc -l < "{log}")
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
{body}
""")
    hook.chmod(0o755)
    return log


def _runs(log: Path) -> int:
    return len(log.read_text().splitlines()) if log.exists() else 0


def _rewrite_main_swarm(main, wt) -> str:  # variant A: the hook edits a Tier B file of the main checkout
    return f'echo hooked > "{main / SWARM_MD}"'


def _inject_tier_b_entry(main, wt) -> str:  # variant B: on the 3rd run (the final stability write-tree) it puts a Tier B entry into the index
    return f'[ "$N" -ge 3 ] && git -C "{wt}" update-index --add --cacheinfo 100644,{_blob(main, "injected" + chr(10))},{SWARM_MD}; true'


def _run_primitives(wt, base) -> dict:
    run(_p.change_set(str(wt), base))
    return run(_p.stage_task(str(wt), base))


@pytest.mark.parametrize("body_for", [_rewrite_main_swarm, _inject_tier_b_entry], ids=["A-rewrites-main-checkout", "B-injects-index-entry"])
def test_post_index_change_hook_does_not_run(dot, body_for):
    main, wt, base = dot
    log = _install_post_index_change(main, body_for(main, wt))
    _w(wt / "src/n.go")
    before = (main / SWARM_MD).read_text()
    r = _run_primitives(wt, base)
    assert _runs(log) == 0, log.read_text()
    assert (main / SWARM_MD).read_text() == before
    assert r["exit_code"] == 0 and r["staged"] == ["src/n.go"] and r["tier_b"] == [], r
    assert _nt(r, wt)["staged"] == ["src/n.go"]  # the tree is the index as written, nothing injected
    assert _git(wt, "diff", "--cached", "--name-only") == "src/n.go\n"


@pytest.mark.parametrize("body_for, effect", [(_rewrite_main_swarm, "main"), (_inject_tier_b_entry, "index")], ids=["A", "B"])
def test_post_index_change_hook_negative_control(dot, monkeypatch, body_for, effect):
    """Run against the REAL repository without `core.hooksPath=/dev/null`, the same hooks run and do what the Checker measured.
    T6c a11: dropping the setting alone no longer shows anything (the shadow has no hooks at all), so the control also swaps the shadow
    for the real git dir (`_unshadowed`)."""
    main, wt, base = dot
    log = _install_post_index_change(main, body_for(main, wt))
    _w(wt / "src/n.go")
    _unshadowed(monkeypatch, drop_config=("core.hooksPath",))
    before = (main / SWARM_MD).read_text()
    r = _run_primitives(wt, base)
    # update-index + write-tree on the private index, read-tree + write-tree on the real one (measured, git 2.54)
    assert _runs(log) == 4, log.read_text()
    if effect == "main":
        assert (main / SWARM_MD).read_text() == "hooked\n" != before
    else:  # the hook writes the REAL index after read-tree (run 3): the final write-tree re-check refuses
        assert r["exit_code"] != 0 and "changed while" in r["error"] and "tree" not in r, r
        assert SWARM_MD in _git(wt, "diff", "--cached", "--name-only")  # ... and the index does hold the Tier B entry


def _a7_way(wt, base) -> subprocess.CompletedProcess:
    """The attempt-7 method, for negative controls: a working-tree `git diff <base>` with every override as `-c k=v` (so a key with
    `=` in its subsection is split there) and no GIT_CONFIG_COUNT."""
    keys = subprocess.run(["git", "-C", str(wt), "config", "-z", "--name-only", "--get-regexp", r"^(filter|merge)\."],
                          capture_output=True, check=False).stdout.decode().split("\0")
    drivers = [(k, "") for k in keys if k.rsplit(".", 1)[-1] in ("clean", "smudge", "process", "driver") and k.count(".") >= 2]
    over = [x for k, v in (*sa._NO_DISTORT_CONFIG, *drivers) for x in ("-c", f"{k}={v}")]
    env = {k: v for k, v in os.environ.items() if k not in sa._GIT_LOCAL_ENV} | sa._NO_DISTORT_ENV
    return subprocess.run(["git", "-C", str(wt), *over, "diff", "--ignore-submodules=none", "--name-only", base],
                          env=env, capture_output=True, check=False)


def _all_traps(main, marks: Path) -> None:
    """Everything a maker can write into the shared git dir that names a command (each one touches a file in `marks`): every hook, in
    <common dir>/hooks AND in a core.hooksPath dir; core.fsmonitor/pager/editor/askPass/sshCommand/gitProxy/alternateRefsCommand;
    filter/diff/merge drivers (names with `=` included) selected by <common dir>/info/attributes and by a core.attributesFile;
    include.path (a file with more traps); diff.external, credential.helper, gpg.program + commit.gpgSign + merge.verifySignatures,
    gc.auto, maintenance.auto; a promisor remote whose uploadpack runs on a lazy fetch (+ extensions.partialClone); an
    objects/info/alternates into another repository that carries the same kind of traps. All objects stay present (positive path)."""
    marks.mkdir()
    hook_dirs = [main / ".git/hooks", marks.parent / "hooks-path"]
    for d in hook_dirs:
        d.mkdir(exist_ok=True)
        for h in ("pre-commit", "prepare-commit-msg", "commit-msg", "post-commit", "pre-merge-commit", "post-merge", "post-checkout",
                  "post-rewrite", "reference-transaction", "post-index-change", "fsmonitor-watchman", "pre-auto-gc"):
            (d / h).write_text(f"#!/bin/sh\ntouch {marks}/{d.name}-{h}\n")
            (d / h).chmod(0o755)
    gpg = _w(marks.parent / "gpg-trap", f"#!/bin/sh\ntouch {marks}/gpg\nexit 1\n")
    gpg.chmod(0o755)
    attrs = _w(marks.parent / "attributes-trap", "*.go filter=f diff=x merge=m=n\n*.md filter=x=y merge=d\n")
    inc = _w(marks.parent / "include-trap", f"[core]\n\tfsmonitor = {marks}/incfsm\n\teditor = touch {marks}/inceditor\n")
    rem = marks.parent / "promisor.git"
    _git(marks.parent, "init", "-q", "--bare", str(rem))
    alt = marks.parent / "alt"
    _git(marks.parent, "init", "-q", str(alt))
    _git(alt, "config", "core.fsmonitor", f"{marks}/altfsm")
    _w(alt / ".git/info/attributes", "* filter=alt\n")
    _git(alt, "config", "filter.alt.clean", f"touch {marks}/altclean; cat")
    for k, v in {"core.fsmonitor": f"{marks}/fsm", "diff.external": f"{marks}/ext", "core.pager": f"touch {marks}/pager",
                 "core.editor": f"touch {marks}/editor", "core.askPass": f"{marks}/askpass", "core.gitProxy": f"{marks}/proxy",
                 "core.hooksPath": str(hook_dirs[1]), "core.attributesFile": str(attrs), "include.path": str(inc),
                 "diff.x.command": f"{marks}/dcmd", "diff.x.textconv": f"touch {marks}/tc",
                 "filter.f.clean": f"touch {marks}/clean; cat", "filter.f.smudge": f"touch {marks}/smudge; cat",
                 "filter.x=y.clean": f"touch {marks}/eqclean; cat", "filter.x=y.smudge": f"touch {marks}/eqsmudge; cat",
                 "merge.m=n.driver": f"touch {marks}/eqmerge; cp %B %A", "merge.d.driver": f"touch {marks}/merge; cp %B %A",
                 "core.sshCommand": f"touch {marks}/ssh", "credential.helper": f"!touch {marks}/cred",
                 "gpg.program": str(gpg), "commit.gpgSign": "true", "merge.verifySignatures": "true",
                 "core.alternateRefsCommand": f"touch {marks}/altrefs", "gc.auto": "1", "maintenance.auto": "true",
                 "remote.evil.url": str(rem), "remote.evil.promisor": "true",
                 "remote.evil.uploadpack": f"touch {marks}/uploadpack; git-upload-pack",
                 "core.repositoryformatversion": "1", "extensions.partialClone": "evil"}.items():
        _git(main, "config", k, v)
    _w(main / ".git/info/attributes", "*.go filter=f diff=x merge=m=n\n*.md filter=x=y merge=d\n")
    _w(main / ".git/info/exclude", "build/\n")
    _w(main / ".git/objects/info/alternates", f"{alt}/.git/objects\n")


def test_no_child_process_is_started_by_any_primitive(dot, tmp_path, monkeypatch):
    """GIT_TRACE2_EVENT: git starts no child at all (hook, filter, fsmonitor, external diff, merge driver, lazy fetch, ...) in the seven
    functions, although every trap of `_all_traps` is set, incoming reaches a real content merge (a driver would run there) and the
    merge checkout rewrites files of the mission worktree (a smudge filter would run there). (`child_start` is the trace2 event of any
    spawned process, hooks included.) T6c a11: incoming is no longer refused for configured drivers (it used to be); commit_tree /
    update_ref (both modes) and the promisor / alternates / core.* / include.path traps are new. Negative controls: the a7 method
    (`-c` overrides + a working-tree diff) and the primitives themselves run against the real git dir (`_unshadowed`, with only
    core.hooksPath=/dev/null dropped) both start children."""
    main, wt, base = dot
    _w(wt / "src/c.go")
    _commit(wt, "src/c.go")  # something for incoming/verify_merge to look at; committed before the traps exist
    mission = Path(run(sa.worktree_alloc("mission", cwd=str(main)))["path"])  # at base: merging the task changes no conflict
    _diverged(main)          # main vs branch `task`: a content merge of src/a.go, where a merge driver would be run
    main_head, br = _git(main, "rev-parse", "HEAD").strip(), _branch(wt)
    marks = tmp_path / "marks"
    _all_traps(main, marks)
    _w(wt / "src/n.go")
    _w(wt / "src/a.go", "changed\n")
    _w(wt / "README.md", "changed\n")
    _w(wt / "build/out.md")  # ignored: Tier B checked, never staged (check-ignore runs)
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    r = _run_primitives(wt, base)
    assert r["exit_code"] == 0 and r["staged"] == ["README.md", "src/a.go", "src/n.go"], r
    assert run(_p.tier_b_hits(str(wt), ["src/a.go"]))["exit_code"] == 0
    c = run(_p.commit_tree(str(wt), r["tree"], [r["head"]], "task"))
    assert run(_p.update_ref(str(wt), c["commit"], r["head"]))["exit_code"] == 0, c
    merged = run(_p.incoming(str(main), "task"))  # a content merge where `m=n` would be selected: plain text merge
    assert merged["exit_code"] == 0 and merged["paths"] == ["src/a.go"], merged
    assert run(_p.verify_merge(str(main), main_head))["exit_code"] == 0
    inc = run(_p.incoming(str(mission), br))
    mc = run(_p.commit_tree(str(mission), inc["tree"], [inc["head"], inc["sha"]], "merge"))
    u = run(_p.update_ref(str(mission), mc["commit"], inc["head"], checkout=True))
    assert u["exit_code"] == 0 and (mission / "src/n.go").exists(), (inc, mc, u)
    assert run(_p.verify_merge(str(mission), inc["head"]))["exit_code"] == 0
    events = [json.loads(line) for line in trace.read_text().splitlines()]
    assert sum(e["event"] == "version" for e in events) > 10  # the trace did record the adapter's git processes
    assert [e for e in events if e["event"] == "child_start"] == []
    assert sorted(p.name for p in marks.iterdir()) == []
    trace.unlink()
    _a7_way(wt, base)  # negative control 1
    assert _child_starts(trace) and "eqclean" in {p.name for p in marks.iterdir()}
    trace.unlink()
    for p in marks.iterdir():
        p.unlink()
    _w(wt / "src/n2.go")
    with monkeypatch.context() as mp:  # negative control 2: the adapter's own git commands with the REAL git dir
        _unshadowed(mp, drop_config=("core.hooksPath",))
        run(_p.stage_task(str(wt), base))
    assert _child_starts(trace) and "hooks-path-post-index-change" in {p.name for p in marks.iterdir()}, sorted(marks.iterdir())


def test_nested_repository_with_its_own_filter_is_refused_before_git_reads_it(dot, tmp_path, monkeypatch):
    """Checker a7 finding 2: a gitlink + a checked-out nested repository whose OWN info/attributes + config name a clean filter.
    A working-tree diff makes git run `git status` inside it, which runs that filter (it rewrote the main checkout's Tier B file).
    Now the Python scan refuses the nested repository and no git process is started inside it; negative control: the a7 method."""
    main, wt, base = dot
    marker = tmp_path / "maker-code-ran"
    evil = _w(tmp_path / "evil.sh", f"#!/bin/sh\necho ran >> {marker}\necho PWNED > {main / SWARM_MD}\ncat\n")
    evil.chmod(0o755)
    sub = wt / "sub"
    _nested_repo(sub)
    _git(wt, "add", "sub")  # a gitlink in the worktree's index, no .gitmodules
    _w(sub / ".git/info/attributes", "* filter=s\n")
    _git(sub, "config", "filter.s.clean", str(evil))
    _w(sub / "f", "y\n")  # same size, racily clean: `git status` in sub must hash it, through the filter
    before = (main / SWARM_MD).read_text()
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    for r in (run(_p.change_set(str(wt), base)), run(_p.stage_task(str(wt), base))):
        assert r["exit_code"] != 0 and "nested git repository" in r["error"] and "'sub'" in r["error"], r
    assert _child_starts(trace) == [] and not marker.exists() and (main / SWARM_MD).read_text() == before
    trace.unlink()
    _a7_way(wt, base)  # negative control
    assert _child_starts(trace) and marker.exists() and (main / SWARM_MD).read_text() == "PWNED\n"


# ---- stage_task: HEAD moved behind/away from base, and zero_diff judged on the tree -------------------------------------
def _stage_checked(wt, base) -> dict:
    return run(_p.stage_task(str(wt), base))


def test_head_reset_behind_base_is_an_error_not_zero_diff(dot):
    """Checker: `git reset --hard base~1` -> stage_task said zero_diff True while the tree it returned differs from base's by the
    reverse of base's own commit (the task's effect silently dropped). Now an error, nothing staged."""
    main, wt, _ = dot
    _w(wt / "src/g.go")
    _commit(wt, "src/g.go", msg="task base")
    base = _git(wt, "rev-parse", "HEAD").strip()
    _git(wt, "reset", "-q", "--hard", "HEAD~1")
    r = _stage_checked(wt, base)
    assert r["exit_code"] != 0 and "ancestor" in r["error"] and "tree" not in r and "zero_diff" not in r, r
    assert _git(wt, "diff", "--cached", "--name-only") == ""


def test_head_reset_behind_base_negative_control(dot):
    """The scenario is real: the old rule (nothing staged and no commits in base..HEAD) holds here, yet base..HEAD's tree deletes src/g.go."""
    _, wt, _ = dot
    _w(wt / "src/g.go")
    _commit(wt, "src/g.go", msg="task base")
    base = _git(wt, "rev-parse", "HEAD").strip()
    _git(wt, "reset", "-q", "--hard", "HEAD~1")
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] == 0 and cs["commits"] == 0, cs
    assert _git(wt, "diff-tree", "-r", "--name-status", base, "HEAD") == "D\tsrc/g.go\n"
    assert _git(wt, "rev-parse", "HEAD^{tree}").strip() != _git(wt, "rev-parse", base + "^{tree}").strip()


def test_head_on_an_unrelated_branch_is_an_error(dot):
    _, wt, base = dot
    _git(wt, "checkout", "-q", "--orphan", "other")
    _git(wt, "rm", "-rqf", "--", ".")
    _w(wt / "src/z.go")
    r = _stage_checked(wt, base)  # T6c a11: Python's HEAD read reports the unborn branch first (it used to be merge-base failing)
    assert r["exit_code"] != 0 and "unborn" in r["error"] and "tree" not in r, r
    _commit(wt, "src/z.go", msg="root")  # a committed unrelated root: the ancestry check
    r = _stage_checked(wt, base)
    assert r["exit_code"] != 0 and "ancestor" in r["error"] and "tree" not in r, r


def test_zero_diff_follows_the_tree_not_the_commit_count(dot):
    """Commits made and then undone leave the tree equal to base's: zero_diff True (committing it changes nothing). A committed
    change that is still in the tree stays zero_diff False."""
    _, wt, base = dot
    original = (wt / "src/a.go").read_text()
    _w(wt / "src/a.go", "changed\n")
    _commit(wt, "src/a.go", msg="change")
    r = _stage_checked(wt, base)
    assert r["exit_code"] == 0 and r["zero_diff"] is False and r["staged"] == [], r
    _w(wt / "src/a.go", original)
    _commit(wt, "src/a.go", msg="revert")
    r = _stage_checked(wt, base)
    assert r["exit_code"] == 0 and r["zero_diff"] is True and r["staged"] == [], r
    assert r["tree"] == _git(wt, "rev-parse", base + "^{tree}").strip()


# ---- T6c attempt 10: the caller's commit / merge, exactly as SKILL.md "Commit and merge" writes it ------------------------
SKILL_MD = Path(sa.__file__).resolve().parents[2] / "SKILL.md"


def _doc_blocks() -> list[str]:
    """The two python blocks of SKILL.md's "Commit and merge" section: commit, merge (T6c a11: was setup + commit + merge)."""
    section = SKILL_MD.read_text().split("## Commit and merge (caller side)\n", 1)[1].split("\n## ", 1)[0]
    blocks = re.findall(r"^```python\n(.*?)^```$", section, re.S | re.M)
    assert len(blocks) == 2, blocks
    return blocks


def _as_coroutine(*blocks: str) -> str:
    """The blocks as the REPL runs them (top-level await): the body of one coroutine that returns its variables."""
    import textwrap
    return "async def _doc():\n" + textwrap.indent("\n".join(blocks), "    ") + "\n    return locals()\n"


def _run_doc(*blocks: str, **names) -> dict:
    ns = {"swarm_adapter": sa, **names}
    exec(compile(_as_coroutine(*blocks), str(SKILL_MD), "exec"), ns)
    return run(ns["_doc"]())


def _git_traps(main, marks: Path, *, attributes: bool = True) -> None:
    """What a maker can write into the shared git dir: every hook, fsmonitor, signing (gpg.program + commit.gpgSign, signature
    verification on merge), auto gc/maintenance, and (attributes=True) a clean/smudge filter named `x=y` (`-c` cannot blank it)
    selected for every path by <common dir>/info/attributes (no option disables that file). Each one touches a file in `marks`."""
    marks.mkdir()
    hooks = main / ".git/hooks"
    hooks.mkdir(exist_ok=True)
    for h in ("pre-commit", "prepare-commit-msg", "commit-msg", "post-commit", "pre-merge-commit", "post-merge", "post-checkout",
              "post-rewrite", "reference-transaction", "post-index-change", "fsmonitor-watchman"):
        (hooks / h).write_text(f"#!/bin/sh\ntouch {marks}/{h}\n")
        (hooks / h).chmod(0o755)
    gpg = _w(marks.parent / "gpg-trap", f"#!/bin/sh\ntouch {marks}/gpg\nexit 1\n")
    gpg.chmod(0o755)
    for k, v in {"core.fsmonitor": f"{marks}/fsm", "gpg.program": str(gpg), "commit.gpgSign": "true",
                 "merge.verifySignatures": "true", "gc.auto": "1", "maintenance.auto": "true",
                 "filter.x=y.clean": f"touch {marks}/eqclean; cat", "filter.x=y.smudge": f"touch {marks}/eqsmudge; cat"}.items():
        _git(main, "config", k, v)
    if attributes:
        _w(main / ".git/info/attributes", "* filter=x=y\n")


def _events(trace: Path) -> list[dict]:
    return [json.loads(line) for line in trace.read_text().splitlines()]


def _staged_task(dot, tmp_path, monkeypatch) -> tuple:
    """stage_task's verified result for a task with a new and a changed file, then every trap (`_all_traps`), then tracing on."""
    main, wt, base = dot
    _w(wt / "src/n.go")
    _w(wt / "src/a.go", "changed\n")
    st = run(_p.stage_task(str(wt), base))
    assert st["exit_code"] == 0 and st["staged"] == ["src/a.go", "src/n.go"], st
    old = _git(wt, "rev-parse", "HEAD").strip()
    marks = tmp_path / "marks"
    _all_traps(main, marks)
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    return wt, st, old, marks, trace


def test_skill_commit_steps_start_no_child_and_commit_exactly_the_tree(dot, tmp_path, monkeypatch):
    """Checker a9/a10: a plain `git commit` after stage_task re-hashes the files through the maker's info/attributes clean filter and
    runs `git maintenance`; any git command in the repository lazily fetches a missing object through the promisor remote. The SKILL.md
    commit block (commit_tree + update_ref, run here verbatim) starts no process at all under every trap, commits exactly stage_task's
    tree on top of the old HEAD, moves the swarm-prime branch, and is not signed."""
    wt, st, old, marks, trace = _staged_task(dot, tmp_path, monkeypatch)
    commit, _ = _doc_blocks()
    got = _run_doc(commit, wt={"path": str(wt)}, st=st, msg="task t1", cd=_Pinned._kw(wt)["expect_common_dir"])
    monkeypatch.delenv("GIT_TRACE2_EVENT")
    events = _events(trace)
    assert sum(e["event"] == "version" for e in events) >= 5  # the trace did record the git processes of the steps
    assert [e for e in events if e["event"] == "child_start"] == []
    assert sorted(p.name for p in marks.iterdir()) == []
    assert st["head"] == old and got["u"] == {"ref": f"refs/heads/{_branch(wt)}", "old": old, "new": got["c"]["commit"], "exit_code": 0}
    assert _git(wt, "rev-parse", "HEAD").strip() == got["c"]["commit"] != old
    assert _git(wt, "rev-parse", "HEAD^{tree}").strip() == st["tree"] and _git(wt, "rev-parse", "HEAD^").strip() == old
    body = _git(wt, "cat-file", "commit", "HEAD")
    assert "gpgsig" not in body and body.endswith("\ntask t1\n") and f"\nparent {old}\n" in body, body


def test_skill_commit_negative_control_plain_git_commit_runs_maker_code(dot, tmp_path, monkeypatch):
    """The Checker's measurement, pinned: on the same staged index and traps, `git -c core.hooksPath=/dev/null commit --no-verify`
    (signing switched off so the commit can complete) runs the maker's clean filter and `git maintenance run --auto`."""
    wt, st, _, marks, trace = _staged_task(dot, tmp_path, monkeypatch)
    subprocess.run(["git", "-C", str(wt), "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                    "commit", "--no-verify", "-q", "-m", "plain"], check=True, capture_output=True)
    monkeypatch.delenv("GIT_TRACE2_EVENT")
    starts = [e["argv"] for e in _events(trace) if e["event"] == "child_start"]
    assert any(a[:3] == ["git", "maintenance", "run"] for a in starts), starts
    assert any("eqclean" in " ".join(a) for a in starts) and "eqclean" in {p.name for p in marks.iterdir()}, starts


def test_skill_commit_refuses_a_moved_branch_and_ignores_a_late_index_write(dot):
    """T6c a11 (was: "refuses a moved HEAD and a changed index"). The commit block commits stage_task's verified TREE, not the index:
    an index entry written after stage_task returned is simply not in the commit (it used to be caught by a write-tree check). A
    branch that moved after stage_task makes update_ref's compare-and-swap refuse: STOP, nothing moved."""
    _, wt, base = dot
    cd = _Pinned._kw(wt)["expect_common_dir"]
    commit, _ = _doc_blocks()
    _w(wt / "src/n.go")
    st = run(_p.stage_task(str(wt), base))
    _git(wt, "update-index", "--add", "--cacheinfo", f"100644,{_blob(wt, 'late' + chr(10))},src/late.go")  # a leftover process
    _run_doc(commit, wt={"path": str(wt)}, st=st, msg="m", cd=cd)
    assert _git(wt, "rev-parse", "HEAD^{tree}").strip() == st["tree"]
    assert "src/late.go" not in _git(wt, "ls-tree", "-r", "--name-only", "HEAD")
    _w(wt / "src/n2.go")
    st2 = run(_p.stage_task(str(wt), base))
    moved = _git(wt, "commit-tree", st2["head"] + "^{tree}", "-p", st2["head"], "-m", "moved").strip()
    _git(wt, "update-ref", f"refs/heads/{_branch(wt)}", moved)  # the maker moves the branch after stage_task
    with pytest.raises(RuntimeError, match="STOP: update_ref"):
        _run_doc(commit, wt={"path": str(wt)}, st=st2, msg="m", cd=cd)
    assert _git(wt, "rev-parse", "HEAD").strip() == moved


def test_commit_tree_signs_only_with_dash_s(dot, tmp_path, monkeypatch):
    """The signing note of SKILL.md, measured: with the maker's commit.gpgSign=true + gpg.program, plain commit-tree
    still starts no process and writes no signature; only `-S` runs gpg.program (which is why the steps never pass it)."""
    main, wt, _ = dot
    head = _git(wt, "rev-parse", "HEAD").strip()
    marks = tmp_path / "marks"
    _git_traps(main, marks, attributes=False)
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    new = _git(wt, "commit-tree", head + "^{tree}", "-p", head, "-m", "x").strip()
    assert [e for e in _events(trace) if e["event"] == "child_start"] == [] and "gpgsig" not in _git(wt, "cat-file", "commit", new)
    trace.unlink()
    assert subprocess.run(["git", "-C", str(wt), "commit-tree", "-S", head + "^{tree}", "-p", head, "-m", "x"],
                          capture_output=True).returncode != 0  # the trap gpg exits 1
    assert [e for e in _events(trace) if e["event"] == "child_start"] and "gpg" in {p.name for p in marks.iterdir()}


def _fake_signed(wt, branch: str) -> None:
    """Rewrite the tip of `branch` into a commit carrying a (bogus) gpgsig header: merge.verifySignatures then runs gpg.program on it."""
    body = _git(wt, "cat-file", "commit", branch)
    head, msg = body.split("\n\n", 1)
    sig = "gpgsig -----BEGIN PGP SIGNATURE-----\n \n iQEzBAABCAAdFiEE\n -----END PGP SIGNATURE-----"
    new = subprocess.run(["git", "hash-object", "-t", "commit", "-w", "--stdin"], cwd=wt, input=f"{head}\n{sig}\n\n{msg}",
                         check=True, capture_output=True, text=True).stdout.strip()
    _git(wt, "update-ref", f"refs/heads/{branch}", new)


def _mission_ready(mission, tmp_path, monkeypatch) -> tuple:
    main, m, t, br = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    _fake_signed(t, br)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and run(_p.tier_b_hits(str(m), inc["paths"]))["hits"] == [], inc
    marks = tmp_path / "marks"
    _all_traps(main, marks)  # T6c a11: info/attributes filters included (the merge checkout runs in the shadow)
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    return m, inc, marks, trace


def test_skill_merge_steps_start_no_child_and_pass_verify_merge(mission, tmp_path, monkeypatch):
    """The SKILL.md merge block, verbatim, under every trap: no process at all (no hook, filter, driver, signing, signature
    verification of the gpgsig-carrying task tip, fsmonitor, maintenance or lazy fetch; T6c a10's `git merge` still started its own
    `git stash create`); the merge commit is incoming's tree with parents [head, sha], the mission worktree and index follow it, and
    verify_merge passes."""
    m, inc, marks, trace = _mission_ready(mission, tmp_path, monkeypatch)
    _, merge = _doc_blocks()
    cd = _Pinned._kw(m)["expect_common_dir"]
    got = _run_doc(merge, mission_wt=str(m), inc=inc, msg="merge t1", cd=cd)
    monkeypatch.delenv("GIT_TRACE2_EVENT")
    events = _events(trace)
    assert sum(e["event"] == "version" for e in events) >= 4
    assert [e["argv"] for e in events if e["event"] == "child_start"] == []
    assert sorted(p.name for p in marks.iterdir()) == []
    assert got["vm"]["exit_code"] == 0 and got["vm"]["paths"] == ["src/t.go"], got["vm"]
    assert _git(m, "rev-parse", "HEAD^{tree}").strip() == inc["tree"]
    assert _git(m, "rev-parse", "HEAD^1", "HEAD^2").split() == [inc["head"], inc["sha"]]
    assert "gpgsig" not in _git(m, "cat-file", "commit", "HEAD")
    assert (m / "src/t.go").read_text() == "x\n" and _git(m, "ls-files", "-s", "src/t.go").split()[1] == _blob(m, "x\n")


def test_skill_merge_negative_control_plain_merge_runs_maker_code(mission, tmp_path, monkeypatch):
    """Same traps, `git -c commit.gpgsign=false merge --no-ff --no-verify <sha>` in the real repository: the configured fsmonitor and
    gpg.program (merge.verifySignatures on the gpgsig-carrying task tip) run; the trap gpg fails the check, so the merge stops
    there (so the merge test above is not vacuous)."""
    m, inc, marks, trace = _mission_ready(mission, tmp_path, monkeypatch)
    p = subprocess.run(["git", "-C", str(m), "-c", "commit.gpgsign=false", "merge", "--no-ff", "--no-verify", "--no-edit", inc["sha"]],
                       capture_output=True, text=True)
    monkeypatch.delenv("GIT_TRACE2_EVENT")
    assert [e for e in _events(trace) if e["event"] == "child_start"], p
    assert "gpg" in {x.name for x in marks.iterdir()}, sorted(marks.iterdir())


def _git_calls(block: str) -> list[str]:
    import ast
    tree = ast.parse(_as_coroutine(block))
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and getattr(n.func, "id", None) == "git"]
    return [ast.unparse(n) for n in sorted(calls, key=lambda n: (n.lineno, n.col_offset))]  # source order (ast.walk is breadth-first)


def _calls(block: str) -> list[str]:
    import ast
    tree = ast.parse(_as_coroutine(block))
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
             and getattr(n.func.value, "id", None) == "swarm_adapter"]
    return [ast.unparse(n) for n in sorted(calls, key=lambda n: (n.lineno, n.col_offset))]


def test_skill_blocks_call_only_the_adapter_and_the_notes_list_the_shadow_settings():
    """Static (T6c a11; was "blocks and git_env agree"): the commit and merge blocks are adapter calls only (no git, no subprocess, no
    decide_shell: nothing runs in the repository), exactly these; the Notes list every setting `_senv` applies."""
    import ast
    commit, merge = _doc_blocks()
    assert _calls(commit) == [
        "swarm_adapter.commit_tree(wt['path'], st['tree'], [st['head']], msg, expect_common_dir=cd)",
        "swarm_adapter.update_ref(wt['path'], c['commit'], st['head'], expect_common_dir=cd)",
    ]
    assert _calls(merge) == [
        "swarm_adapter.tier_b_hits(mission_wt, inc['paths'], expect_common_dir=cd)",  # T6c a13: the block checks before it writes
        "swarm_adapter.commit_tree(mission_wt, inc['tree'], [inc['head'], inc['sha']], msg, expect_common_dir=cd)",
        "swarm_adapter.update_ref(mission_wt, c['commit'], inc['head'], checkout=True, expect_common_dir=cd)",
        "swarm_adapter.verify_merge(mission_wt, inc['head'], expect_common_dir=cd)",
    ]
    names = {n.id for b in (commit, merge) for n in ast.walk(ast.parse(_as_coroutine(b))) if isinstance(n, ast.Name)}
    assert not names & {"subprocess", "git", "shlex", "os"}, names
    assert not hasattr(sa, "git_env")
    notes = SKILL_MD.read_text().split("**Every git command runs in a private bare shadow repository**", 1)[1].split(
        "The git binary is given only shas", 1)[0]
    listed = re.findall(r"`([a-zA-Z.]+)=([^`=]+)`", notes)
    assert sorted(listed) == sorted(p for p in sa._NO_DISTORT_CONFIG if p[0] != "advice.graftFileDeprecated"), listed
    assert [k for k in [*sa._NO_DISTORT_ENV, "GIT_DIR", "GIT_OBJECT_DIRECTORY", "GIT_INDEX_FILE"] if f"`{k}" not in notes] == []


def test_shadow_env_drops_inherited_git_settings_and_is_a_copy(dot, monkeypatch):
    """T6c a11 (git_env is gone: the caller runs no git): `_senv` drops every inherited GIT_* but trace/identity, and never writes
    to os.environ."""
    _, wt, _ = dot
    for k, v in (("GIT_CONFIG_PARAMETERS", "'core.hooksPath'='/x'"), ("GIT_CONFIG_COUNT", "1"), ("GIT_CONFIG_KEY_0", "gc.auto"),
                 ("GIT_CONFIG_VALUE_0", "1"), ("GIT_CONFIG", "/x"), ("GIT_DIR", "/x"), ("GIT_INDEX_FILE", "/x"), ("GIT_EXEC_PATH", "/x"),
                 ("GIT_WORK_TREE", "/x"), ("GIT_COMMON_DIR", "/x"), ("GIT_TRACE2_EVENT", "/dev/null"), ("GIT_AUTHOR_NAME", "a")):
        monkeypatch.setenv(k, v)
    with _opened(wt) as r:
        env = sa._senv(r)
        assert env["GIT_DIR"] == r.sh and env["GIT_INDEX_FILE"] == r.gitdir + "/index" and "GIT_WORK_TREE" not in env
        assert not {"GIT_CONFIG_PARAMETERS", "GIT_CONFIG", "GIT_EXEC_PATH", "GIT_COMMON_DIR"} & set(env), env
        assert env["GIT_TRACE2_EVENT"] == "/dev/null" and env["GIT_AUTHOR_NAME"] == "a" and env["GIT_CONFIG_KEY_0"] != "gc.auto"
        env["GIT_DIR"] = "/y"
        assert os.environ["GIT_DIR"] == "/x" and sa._senv(r)["GIT_DIR"] == r.sh
        assert sa._senv(r, work=True)["GIT_WORK_TREE"] == r.top


# ---- T6c attempt 11: no git command runs in the target repository (shadow repository, refs and location read by Python) ----------
MISSING = "1" * 40


def _promisor_trap(main, marks: Path) -> None:
    """Checker a10: a promisor remote in the shared config. Any git command that needs a missing object fetches it lazily, which runs
    the remote's `uploadpack` command through the shell (touching marks/uploadpack)."""
    marks.mkdir(exist_ok=True)
    rem = marks.parent / "promisor.git"
    _git(marks.parent, "init", "-q", "--bare", str(rem))
    for k, v in {"remote.evil.url": str(rem), "remote.evil.promisor": "true",
                 "remote.evil.uploadpack": f"touch {marks}/uploadpack; git-upload-pack"}.items():
        _git(main, "config", k, v)


def _gitdir(wt) -> Path:
    return Path(_git(wt, "rev-parse", "--absolute-git-dir").strip())


def _lazy_fetch_negative_control(wt, trace: Path, marks: Path) -> None:
    """Plain git in the real repository meets the same missing commit: the promisor's uploadpack runs."""
    trace.unlink(missing_ok=True)
    subprocess.run(["git", "-C", str(wt), "rev-parse", "--verify", "-q", f"{MISSING}^{{commit}}"], capture_output=True, check=False)
    assert _child_starts(trace) and "uploadpack" in {p.name for p in marks.iterdir()}


@pytest.mark.parametrize("where", ["change_set", "stage_task", "incoming", "verify_merge", "commit_tree", "update_ref",
                                   "skill_commit", "skill_merge"])
def test_missing_commit_is_an_error_never_a_lazy_fetch(dot, tmp_path, monkeypatch, where):
    """Checker a10: a promisor remote + HEAD or a branch pointing at a commit that does not exist made git fetch it inside the adapter
    (stage_task / change_set / incoming) and in the SKILL.md commit block, running the maker's `uploadpack`. Now refs are read by
    Python and every git command runs in the shadow (no remote configured) with GIT_NO_LAZY_FETCH: an error, 0 child_start, no
    marker. skill_*: a leftover maker process repoints the branch after the check; the blocks STOP at update_ref's compare-and-swap
    without reading the missing object. Negative control: plain git in the real repository runs the uploadpack."""
    main, wt, base = dot
    marks = tmp_path / "marks"
    kw = _Pinned._kw(wt)
    commit, merge = _doc_blocks()
    _w(wt / "src/n.go")
    st = run(_p.stage_task(str(wt), base))
    assert st["exit_code"] == 0, st
    mission = Path(run(sa.worktree_alloc("mission", cwd=str(main)))["path"])
    if where == "skill_merge":
        c = run(_p.commit_tree(str(wt), st["tree"], [st["head"]], "t"))
        assert run(_p.update_ref(str(wt), c["commit"], st["head"]))["exit_code"] == 0
        inc = run(_p.incoming(str(mission), _branch(wt)))
        assert inc["exit_code"] == 0, inc
    _promisor_trap(main, marks)
    branch_file = _common_dir(wt) / "refs/heads" / _branch(wt)
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    if where in ("change_set", "stage_task"):
        (_gitdir(wt) / "HEAD").write_text(MISSING + "\n")
        r = run(getattr(_p, where)(str(wt), base))
    elif where == "incoming":
        branch_file.write_text(MISSING + "\n")
        r = run(_p.incoming(str(mission), _branch(wt)))
    elif where == "verify_merge":
        (_gitdir(mission) / "HEAD").write_text(MISSING + "\n")
        r = run(_p.verify_merge(str(mission), base))
    elif where == "commit_tree":
        r = run(_p.commit_tree(str(wt), st["tree"], [MISSING], "m"))
    elif where == "update_ref":
        branch_file.write_text(MISSING + "\n")
        r = run(_p.update_ref(str(wt), "2" * 40, MISSING))
    else:
        tgt = wt if where == "skill_commit" else mission
        (_common_dir(tgt) / "refs/heads" / _branch(tgt)).write_text(MISSING + "\n")
        with pytest.raises(RuntimeError, match="STOP: update_ref") as ex:
            if where == "skill_commit":
                _run_doc(commit, wt={"path": str(wt)}, st=st, msg="m", cd=kw["expect_common_dir"])
            else:
                _run_doc(merge, mission_wt=str(mission), inc=inc, msg="m", cd=kw["expect_common_dir"])
        r = {"exit_code": 1, "error": str(ex.value)}
    assert r["exit_code"] != 0 and r["error"] and "paths" not in r and "tree" not in r and "commit" not in r, r
    assert _child_starts(trace) == [] and not list(marks.glob("uploadpack")), r
    _lazy_fetch_negative_control(wt, trace, marks)


def test_lazy_fetch_negative_control_the_adapters_own_commands_against_the_real_repository(dot, tmp_path, monkeypatch):
    """The same change_set (HEAD at a missing commit), its git commands run against the REAL git dir: without GIT_NO_LAZY_FETCH the
    promisor's uploadpack runs; with it (and the real git dir) it does not: the env var is the second layer, the shadow the first."""
    main, wt, base = dot
    marks = tmp_path / "marks"
    _promisor_trap(main, marks)
    (_gitdir(wt) / "HEAD").write_text(MISSING + "\n")
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    with monkeypatch.context() as m:
        _unshadowed(m)
        assert run(_p.change_set(str(wt), base))["exit_code"] != 0
    assert _child_starts(trace) == [] and not list(marks.iterdir())
    with monkeypatch.context() as m:
        _unshadowed(m, drop_env=("GIT_NO_LAZY_FETCH",))
        assert run(_p.change_set(str(wt), base))["exit_code"] != 0
    assert _child_starts(trace) and "uploadpack" in {p.name for p in marks.iterdir()}


def test_the_repository_config_is_never_read(dot, tmp_path, monkeypatch):
    """GIT_TRACE2_CONFIG_PARAMS makes every git process report the value of the named keys from every config it reads: a key that is
    only in the repository's config (directly and through include.path) never shows up in any of the seven functions or the two
    SKILL.md blocks. Negative control: plain git in the checkout reports both."""
    main, wt, base = dot
    _w(wt / "src/n.go")
    _git(main, "config", "swarmtest.direct", "real")
    _w(tmp_path / "inc.cfg", "[swarmtest]\n\tincluded = real\n")
    _git(main, "config", "include.path", str(tmp_path / "inc.cfg"))
    mission = Path(run(sa.worktree_alloc("mission", cwd=str(main)))["path"])
    kw, br = _Pinned._kw(wt), _branch(wt)
    commit, merge = _doc_blocks()
    trace = tmp_path / "trace2.json"
    monkeypatch.setenv("GIT_TRACE2_EVENT", str(trace))
    monkeypatch.setenv("GIT_TRACE2_CONFIG_PARAMS", "swarmtest.*")
    monkeypatch.setattr(sa, "_GIT_VERSION", [])
    assert run(sa.change_set(str(wt), base, **kw))["exit_code"] == 0
    st = run(sa.stage_task(str(wt), base, **kw))
    assert run(sa.tier_b_hits(str(wt), ["src/n.go"], **kw))["exit_code"] == 0
    _run_doc(commit, wt={"path": str(wt)}, st=st, msg="t", cd=kw["expect_common_dir"])
    inc = run(sa.incoming(str(mission), br, **kw))
    got = _run_doc(merge, mission_wt=str(mission), inc=inc, msg="m", cd=kw["expect_common_dir"])
    assert got["vm"]["exit_code"] == 0, got
    events = _events(trace)
    assert sum(e["event"] == "version" for e in events) > 10
    assert [e for e in events if e["event"] == "def_param"] == []
    trace.unlink()
    _git(wt, "rev-parse", "HEAD")
    assert {(e["param"], e["value"]) for e in _events(trace) if e["event"] == "def_param"} == {
        ("swarmtest.direct", "real"), ("swarmtest.included", "real")}


# -- refs read by Python --------------------------------------------------------------------------------------------------------
def test_symref_chain_is_followed_and_a_loop_is_an_error(dot):
    main, wt, base = dot
    common, br = _common_dir(wt), _branch(wt)
    tip = _git(wt, "rev-parse", "HEAD").strip()
    _git(wt, "update-ref", "refs/heads/real-tip", tip)
    (common / "refs/heads" / br).write_text("ref: refs/heads/real-tip\n")  # HEAD -> br -> real-tip -> sha
    cs = run(_p.change_set(str(wt), base))
    assert cs["exit_code"] == 0 and cs["branch"] == br, cs
    (common / "refs/heads/real-tip").write_text(f"ref: refs/heads/{br}\n")  # br <-> real-tip
    for r in (run(_p.change_set(str(wt), base)), run(_p.stage_task(str(wt), base)), run(_p.incoming(str(main), br))):
        assert r["exit_code"] != 0 and "symbolic ref chain" in r["error"] and "paths" not in r, r


def test_packed_refs_only_branches_with_peeled_tags_are_read(dot):
    """`git pack-refs --all` moves every ref into packed-refs (an annotated tag adds a peeled `^` line): HEAD's branch and the task
    branch are read from it; update_ref then writes a loose ref (which wins over the packed one, as in git)."""
    main, wt, base = dot
    _w(wt / "src/t.go")
    _commit(wt, "src/t.go")
    _git(main, "tag", "-a", "-m", "annotated", "v1", base)
    _git(main, "pack-refs", "--all")
    common, br = _common_dir(wt), _branch(wt)
    assert not (common / "refs/heads" / br).exists() and "\n^" in (common / "packed-refs").read_text()
    assert run(_p.change_set(str(wt), base))["branch"] == br
    assert _inc(run(_p.incoming(str(main), br))) == {"paths": ["src/t.go"], "exit_code": 0}
    _w(wt / "src/n.go")
    st = run(_p.stage_task(str(wt), base))
    c = run(_p.commit_tree(str(wt), st["tree"], [st["head"]], "m"))
    assert run(_p.update_ref(str(wt), c["commit"], st["head"]))["exit_code"] == 0
    assert (common / "refs/heads" / br).read_text() == c["commit"] + "\n" and _git(wt, "rev-parse", "HEAD").strip() == c["commit"]


@pytest.mark.parametrize("line", ["garbage", "^" + "a" * 40 + "\n^" + "a" * 40, "a" * 64 + " refs/heads/x", "a" * 40 + " refs/heads/../x",
                                  "a" * 40 + " refs/heads/main"])
def test_malformed_packed_refs_is_an_error(dot, line):
    """Every line is validated (a stray peeled line, a sha256 id, a bad ref name, a duplicate): fail-closed, not skipped."""
    main, wt, base = dot
    _git(main, "pack-refs", "--all")
    br, kw = _branch(wt), _Pinned._kw(main)  # before the corruption (plain git refuses a malformed packed-refs)
    with open(_common_dir(wt) / "packed-refs", "a") as f:
        f.write(line + "\n")
    r = run(sa.incoming(str(main), br, **kw))
    assert r["exit_code"] != 0 and "packed-refs line" in r["error"] and "paths" not in r, r


@pytest.mark.parametrize("value, why", [("zz\n", "neither"), ("a" * 64 + "\n", "sha256"), ("ref: refs/tags/v1\n", "unsupported ref"),
                                        ("ref: refs/heads/../../x\n", "unsupported ref"), ("", "neither"),
                                        ("ref: refs/heads/nope\n", "unborn")])
def test_bad_head_and_branch_values_are_errors(dot, value, why):
    main, wt, base = dot
    br, kw, gd = _branch(wt), _Pinned._kw(wt), _gitdir(wt)  # before the corruption (plain git may no longer accept the checkout)
    good = (gd / "HEAD").read_text()
    (gd / "HEAD").write_text(value)
    for r in (run(sa.change_set(str(wt), base, **kw)), run(sa.stage_task(str(wt), base, **kw)),
              run(sa.verify_merge(str(wt), base, **kw))):
        assert r["exit_code"] != 0 and why in r["error"] and "paths" not in r and "tree" not in r, r
    (gd / "HEAD").write_text(good)
    if why != "unborn":
        (_common_dir(wt) / "refs/heads" / br).write_text(value)
        r = run(sa.incoming(str(main), br, **kw))
        assert r["exit_code"] != 0 and why in r["error"] and "paths" not in r, r


@pytest.mark.parametrize("kind", ["objectformat", "refstorage", "reftable-dir", "shallow", "garbage-config"])
def test_unsupported_repository_formats_are_errors(dot, kind):
    """sha256 / reftable / shallow repositories, read from files (not executed): every function refuses (the shadow could not answer
    for them: other object ids, refs not in files, no shallow list). A config line the parser cannot read is refused too."""
    main, wt, base = dot
    expect = os.path.realpath(main / ".git")
    assert run(sa.change_set(str(wt), base, expect_common_dir=expect))["exit_code"] == 0  # positive control
    common, br, tip = Path(expect), _branch(wt), _git(wt, "rev-parse", "HEAD").strip()  # before the edit
    if kind == "objectformat":
        with open(common / "config", "a") as f:
            f.write("[extensions]\n\tobjectFormat = sha256\n")
    elif kind == "refstorage":
        with open(common / "config", "a") as f:
            f.write('[Extensions]\n\trefStorage = "reftable" ; comment\n')
    elif kind == "reftable-dir":
        (common / "reftable").mkdir()
    elif kind == "shallow":
        (common / "shallow").write_text(base + "\n")
    else:
        with open(common / "config", "a") as f:
            f.write("[core\n")
    for r in (run(sa.change_set(str(wt), base, expect_common_dir=expect)), run(sa.stage_task(str(wt), base, expect_common_dir=expect)),
              run(sa.incoming(str(main), br, expect_common_dir=expect)),
              run(sa.verify_merge(str(main), base, expect_common_dir=expect)),
              run(sa.commit_tree(str(wt), "4b825dc642cb6eb9a060e54bf8d69288fbee4904", [tip], "m", expect_common_dir=expect)),
              run(sa.update_ref(str(wt), tip, tip, expect_common_dir=expect)),
              run(sa.tier_b_hits(str(wt), ["src/a.go"], expect_common_dir=expect))):
        assert r["exit_code"] != 0 and r["error"] and "paths" not in r and "tree" not in r and "commit" not in r, r
        assert {"objectformat": "sha256", "refstorage": "reftable", "reftable-dir": "reftable", "shallow": "shallow",
                "garbage-config": "unparseable config line"}[kind] in r["error"], r


def test_old_git_is_refused(dot, monkeypatch):
    """GIT_NO_LAZY_FETCH needs git >= 2.45: an older git is an error before any repository command runs (fail-closed)."""
    _, wt, base = dot
    monkeypatch.setattr(sa, "_MIN_GIT", (99, 0))
    for r in (run(_p.change_set(str(wt), base)), run(_p.stage_task(str(wt), base)), run(_p.commit_tree(str(wt), base, [base], "m"))):
        assert r["exit_code"] != 0 and "git >= 99.0 is required" in r["error"], r


def test_ref_names_follow_check_ref_format():
    ok = ["refs/heads/a", "refs/heads/swarm-prime/t1-20261014-093724", "refs/heads/日本"]
    bad = ["", "@", "refs/heads/a..b", "refs/heads/.a", "refs/heads/a.lock", "refs/heads/a/", "refs/heads//a", "refs/heads/a b",
           "refs/heads/a~1", "refs/heads/a^", "refs/heads/a:b", "refs/heads/a?", "refs/heads/a*", "refs/heads/a[", "refs/heads/a\\b",
           "refs/heads/a@{1}", "/refs/heads/a", "refs/heads/a.", "refs/heads/a\x7f", "refs/heads/x/.lock/y"]
    assert [n for n in ok if not sa._ref_ok(n)] == [] and [n for n in bad if sa._ref_ok(n)] == []
    for n in ok:  # git agrees
        assert subprocess.run(["git", "check-ref-format", n], capture_output=True).returncode == 0, n
    for n in bad:
        assert subprocess.run(["git", "check-ref-format", n], capture_output=True).returncode != 0, n


# -- commit_tree / update_ref ----------------------------------------------------------------------------------------------------
def _commit_task(wt, base) -> tuple[dict, dict]:
    _w(wt / "src/n.go")
    st = run(_p.stage_task(str(wt), base))
    c = run(_p.commit_tree(str(wt), st["tree"], [st["head"]], "m"))
    assert st["exit_code"] == 0 and c["exit_code"] == 0, (st, c)
    return st, c


def test_update_ref_moves_only_a_swarm_prime_branch_by_one_commit(dot, tmp_path):
    """update_ref is not destructive by construction: HEAD must be a symbolic ref to refs/heads/swarm-prime/*, `new`'s FIRST parent
    must be `old`, and the branch must still be `old`. Each refusal leaves every ref where it was."""
    main, wt, base = dot
    st, c = _commit_task(wt, base)
    br = f"refs/heads/{_branch(wt)}"
    # not a swarm-prime branch (the main checkout's `main`)
    mc = run(_p.commit_tree(str(main), st["tree"], [base], "m"))
    r = run(_p.update_ref(str(main), mc["commit"], base))
    assert r["exit_code"] != 0 and "swarm-prime" in r["error"] and _git(main, "rev-parse", "HEAD").strip() == base, r
    # not a fast-forward by one commit: `new`'s first parent is not `old` (another commit, or `old` only as the second parent)
    other = run(_p.commit_tree(str(wt), st["tree"], [c["commit"]], "x"))["commit"]
    two = run(_p.commit_tree(str(wt), st["tree"], [c["commit"], st["head"]], "x"))["commit"]
    for new in (other, two):
        r = run(_p.update_ref(str(wt), new, st["head"]))
        assert r["exit_code"] != 0 and "first parent" in r["error"], r
    assert _git(wt, "rev-parse", br).strip() == st["head"]
    # a correct one-commit step, but from an `old` the branch is not at (the compare-and-swap)
    d = run(_p.commit_tree(str(wt), st["tree"], [other], "d"))["commit"]
    r = run(_p.update_ref(str(wt), d, other))
    assert r["exit_code"] != 0 and "moved" in r["error"] and _git(wt, "rev-parse", br).strip() == st["head"], r
    # detached HEAD
    _git(wt, "checkout", "-q", "--detach")
    r = run(_p.update_ref(str(wt), c["commit"], st["head"]))
    assert r["exit_code"] != 0 and "swarm-prime" in r["error"], r
    _git(wt, "checkout", "-q", br.removeprefix("refs/heads/"))
    assert run(_p.update_ref(str(wt), c["commit"], st["head"]))["exit_code"] == 0  # positive control
    assert _git(wt, "rev-parse", "HEAD").strip() == c["commit"] and f"refs/heads/{_branch(wt)}" == br


def test_update_ref_respects_a_held_lock_and_a_symlinked_ref_dir(dot, tmp_path):
    main, wt, base = dot
    st, c = _commit_task(wt, base)
    common, name = _common_dir(wt), _branch(wt)
    lock = common / "refs/heads" / (name + ".lock")
    lock.write_text("held\n")
    r = run(_p.update_ref(str(wt), c["commit"], st["head"]))
    assert r["exit_code"] != 0 and "lock exists" in r["error"] and lock.read_text() == "held\n", r  # someone else's lock is kept
    lock.unlink()
    d = common / "refs/heads/swarm-prime"
    elsewhere = tmp_path / "elsewhere"
    shutil.copytree(d, elsewhere)
    shutil.rmtree(d)
    d.symlink_to(elsewhere)  # plain git follows it; the adapter never writes through it
    r = run(_p.update_ref(str(wt), c["commit"], st["head"]))
    assert r["exit_code"] != 0 and (elsewhere / name.removeprefix("swarm-prime/")).read_text().strip() == st["head"], r
    assert not list(elsewhere.glob("*.lock"))


def test_update_ref_checkout_refuses_local_changes_untracked_files_and_staged_changes(mission):
    """checkout=True: read-tree -m -u in the shadow refuses (nothing written, the ref not moved) when a local change or an untracked
    file is in the way, and update_ref refuses up front when the index has staged changes."""
    main, m, t, br = mission
    _w(t / "src/a.go", "task\n")
    _w(t / "src/new.go", "task\n")
    _commit(t, "src/a.go", "src/new.go")
    inc = run(_p.incoming(str(m), br))
    mc = run(_p.commit_tree(str(m), inc["tree"], [inc["head"], inc["sha"]], "merge"))
    head = inc["head"]
    for setup, undo, why in (
            (lambda: _w(m / "src/a.go", "local\n"), lambda: _git(m, "checkout", "-q", "--", "src/a.go"), "read-tree"),
            (lambda: _w(m / "src/new.go", "untracked\n"), lambda: (m / "src/new.go").unlink(), "read-tree"),
            (lambda: (_w(m / "src/z.go"), _git(m, "add", "src/z.go")), lambda: (_git(m, "rm", "-q", "--cached", "src/z.go"),
                                                                                 (m / "src/z.go").unlink()), "staged changes")):
        setup()
        before = {p: (m / p).read_text() for p in ("src/a.go", "src/new.go") if (m / p).exists()}
        r = run(_p.update_ref(str(m), mc["commit"], head, checkout=True))
        assert r["exit_code"] != 0 and why in r["error"], r
        assert _git(m, "rev-parse", "HEAD").strip() == head and {p: (m / p).read_text() for p in before} == before, r
        assert not list(_common_dir(m).glob("refs/heads/swarm-prime/*.lock"))
        undo()
    r = run(_p.update_ref(str(m), mc["commit"], head, checkout=True))  # positive control
    assert r["exit_code"] == 0 and (m / "src/a.go").read_text() == "task\n" and _git(m, "status", "--porcelain") == "", r


def test_update_ref_checkout_refuses_a_nested_repository(mission):
    _, m, t, br = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    inc = run(_p.incoming(str(m), br))
    mc = run(_p.commit_tree(str(m), inc["tree"], [inc["head"], inc["sha"]], "merge"))
    _nested_repo(m / "vendor/x")
    r = run(_p.update_ref(str(m), mc["commit"], inc["head"], checkout=True))
    assert r["exit_code"] != 0 and "nested git repository" in r["error"] and _git(m, "rev-parse", "HEAD").strip() == inc["head"], r


# -- T6c a12: update_ref asks git for the parents, undoes its checkout when the ref write fails; git is run by absolute path -----
def _files(top: Path) -> dict[str, str]:
    """Every working-tree file (the top-level .git excluded) with its content."""
    return {str(p.relative_to(top)): p.read_text() for p in top.rglob("*")
            if p.is_file() and not p.is_symlink() and p.relative_to(top).parts[0] != ".git"}


def _crafted_child(wt, old: str, tree: str) -> str:
    """A commit object whose only `parent <old>` line comes AFTER `committer`: git reads NO parent (a root commit), while a scan of
    every header line finds `old`. Plain `hash-object -t commit -w` (no --literally) writes it."""
    body = f"tree {tree}\nauthor a <a@b> 0 +0000\ncommitter a <a@b> 0 +0000\nparent {old}\n\nlooks like a child of old\n"
    new = subprocess.run(["git", "hash-object", "-t", "commit", "-w", "--stdin"], cwd=wt, input=body, check=True,
                         capture_output=True, text=True).stdout.strip()
    assert _git(wt, "rev-list", "--parents", "-n1", new).split() == [new]  # git: no parent at all
    return new


@pytest.mark.parametrize("checkout", [False, True])
def test_update_ref_takes_the_parents_from_git_not_from_the_object_text(dot, checkout):
    """T6c a11 checker: `parent <old>` placed after `committer` made update_ref move the branch onto a ROOT commit (exit 0), and with
    checkout=True `read-tree -m -u` deleted every file. git's own `rev-list --parents` now decides: refused, nothing changed."""
    _, wt, _ = dot
    old, br = _git(wt, "rev-parse", "HEAD").strip(), f"refs/heads/{_branch(wt)}"
    new = _crafted_child(wt, old, sa._EMPTY_TREE)
    files, itree = _files(wt), _git(wt, "write-tree").strip()
    assert files
    r = run(_p.update_ref(str(wt), new, old, checkout=checkout))
    assert r["exit_code"] != 0 and "first parent" in r["error"], r
    assert _git(wt, "rev-parse", br).strip() == old and _files(wt) == files and _git(wt, "write-tree").strip() == itree, r


@pytest.mark.parametrize("checkout", [False, True])
def test_update_ref_refuses_a_root_commit_an_unrelated_parent_and_old_as_second_parent_only(dot, checkout):
    _, wt, _ = dot
    old, br, tree = _git(wt, "rev-parse", "HEAD").strip(), f"refs/heads/{_branch(wt)}", _git(wt, "rev-parse", "HEAD^{tree}").strip()
    root = _git(wt, "-c", "commit.gpgsign=false", "commit-tree", tree, "-m", "root").strip()
    unrelated = run(_p.commit_tree(str(wt), tree, [root], "u"))["commit"]
    second = run(_p.commit_tree(str(wt), tree, [root, old], "s"))["commit"]
    files = _files(wt)
    for new in (root, unrelated, second):
        r = run(_p.update_ref(str(wt), new, old, checkout=checkout))
        assert r["exit_code"] != 0 and "first parent" in r["error"], (new, r)
        assert _git(wt, "rev-parse", br).strip() == old and _files(wt) == files, r
    good = run(_p.commit_tree(str(wt), tree, [old], "g"))["commit"]
    assert run(_p.update_ref(str(wt), good, old, checkout=checkout))["exit_code"] == 0  # positive control
    assert _git(wt, "rev-parse", br).strip() == good


def test_commit_tree_returns_the_parents_git_wrote(dot):
    """`git commit-tree -p X -p X` drops the duplicate (exit 0, "duplicate parent ignored"): commit_tree returned [X, X] for a
    one-parent commit. The parents are read back from git and must be the ones asked for."""
    _, wt, base = dot
    tree = _git(wt, "rev-parse", "HEAD^{tree}").strip()
    r = run(_p.commit_tree(str(wt), tree, [base, base], "m"))
    assert r["exit_code"] != 0 and "parents" in r["error"] and "commit" not in r, r
    ok = run(_p.commit_tree(str(wt), tree, [base], "m"))
    assert ok["exit_code"] == 0 and _git(wt, "rev-list", "--parents", "-n1", ok["commit"]).split()[1:] == [base], ok


def _merge_ready(mission) -> tuple:
    """(mission worktree, merge commit, its first parent): a task commit ready for update_ref(checkout=True)."""
    _, m, t, br = mission
    _w(t / "src/a.go", "task\n")
    _w(t / "src/new.go", "task\n")
    _commit(t, "src/a.go", "src/new.go")
    inc = run(_p.incoming(str(m), br))
    mc = run(_p.commit_tree(str(m), inc["tree"], [inc["head"], inc["sha"]], "merge"))
    assert inc["exit_code"] == 0 and mc["exit_code"] == 0, (inc, mc)
    return m, mc["commit"], inc["head"]


def test_update_ref_refuses_an_unwritable_ref_before_the_checkout(mission):
    """T6c a11 checker (minor): the branch only in packed-refs and a directory where the loose ref goes: the rename failed AFTER
    `read-tree -m -u` had put `new` into the index and working tree (ref still `old`). It is now refused under the lock first."""
    m, new, old = _merge_ready(mission)
    br, common = _branch(m), _common_dir(m)
    _git(m, "pack-refs", "--all")
    files, itree = _files(m), _git(m, "write-tree").strip()
    loose = common / "refs/heads" / br
    assert not loose.exists() and f"{old} refs/heads/{br}\n" in (common / "packed-refs").read_text()
    kw = _Pinned._kw(m)  # before the directory goes in
    loose.mkdir(parents=True)  # pack-refs pruned the empty refs/heads/swarm-prime
    r = run(sa.update_ref(str(m), new, old, checkout=True, **kw))
    assert r["exit_code"] != 0 and "not a regular file" in r["error"], r
    assert _files(m) == files and _git(m, "write-tree").strip() == itree and loose.is_dir() and not any(loose.iterdir()), r
    assert f"{old} refs/heads/{br}\n" in (common / "packed-refs").read_text() and not list(loose.parent.glob("*.lock")), r


@pytest.mark.parametrize("blocked", [False, True])
def test_update_ref_restores_the_checkout_when_the_ref_write_fails(mission, monkeypatch, blocked):
    """A ref write that fails after the checkout (here: the rename of the lock, injected) puts the index and working tree back to
    `old` with `read-tree -m -u new old`; if git refuses that (a local change made meanwhile), the error says so."""
    m, new, old = _merge_ready(mission)
    br, common = f"refs/heads/{_branch(m)}", _common_dir(m)
    files, itree = _files(m), _git(m, "write-tree").strip()
    real = os.rename

    def rename(src, dst, **kw):
        if str(src).endswith(".lock"):
            if blocked:
                (m / "src/a.go").write_text("local\n")  # changed after the checkout: undoing it would overwrite this
            raise OSError(errno.EIO, "injected rename failure")
        return real(src, dst, **kw)

    monkeypatch.setattr(sa.os, "rename", rename)
    r = run(_p.update_ref(str(m), new, old, checkout=True))
    monkeypatch.setattr(sa.os, "rename", real)
    assert r["exit_code"] != 0 and "injected rename failure" in r["error"], r
    assert _git(m, "rev-parse", br).strip() == old and not list(common.glob("refs/heads/swarm-prime/*.lock")), r
    if blocked:
        assert "could NOT be restored" in r["error"] and (m / "src/a.go").read_text() == "local\n", r
    else:
        assert "were restored" in r["error"] and _files(m) == files and _git(m, "write-tree").strip() == itree, r
        assert _git(m, "status", "--porcelain") == "", r


@pytest.mark.parametrize("entry", [".", ""])
def test_git_runs_by_absolute_path_never_from_a_relative_path_entry(mission, tmp_path, monkeypatch, entry):
    """T6c a11 checker (minor): with GIT_WORK_TREE git ran with cwd = the maker's worktree, so an empty or `.` PATH entry executed a
    `git` file there. The binary is now resolved once over the ABSOLUTE PATH entries only, and every command runs in the shadow's dir."""
    m, new, old = _merge_ready(mission)
    _, _, t, _ = mission
    base_t, kw = _git(t, "rev-parse", "HEAD").strip(), _Pinned._kw(m)
    real, marks = shutil.which("git"), tmp_path / "marks"
    marks.mkdir()
    for top in (m, t):
        _w(top / "git", f'#!/bin/sh\ntouch {marks}/ran\nexec {real} "$@"\n').chmod(0o755)
    _w(t / "src/n.go")
    monkeypatch.setenv("PATH", entry + os.pathsep + os.environ["PATH"])
    monkeypatch.setattr(sa, "_GIT_EXE", [])
    monkeypatch.setattr(sa, "_GIT_VERSION", [])
    st = run(sa.stage_task(str(t), base_t, **kw))  # check-ignore reads the working tree
    assert st["exit_code"] == 0 and "git" in st["staged"], st
    u = run(sa.update_ref(str(m), new, old, checkout=True, **kw))  # read-tree -m -u writes it
    assert u["exit_code"] == 0 and sa._GIT_EXE == [real], u
    assert not (marks / "ran").exists()
    subprocess.run(["git", "version"], cwd=m, capture_output=True, check=True)  # negative control: a PATH lookup from there runs it
    assert (marks / "ran").exists()


@pytest.mark.parametrize("where", ["checkout", "tmp"])
def test_a_git_binary_in_the_checkout_or_the_temp_dir_is_refused(dot, tmp_path, monkeypatch, where):
    _, wt, base = dot
    kw = _Pinned._kw(wt)
    d = wt / "bin" if where == "checkout" else tmp_path / "bin"
    _w(d / "git", f'#!/bin/sh\nexec {shutil.which("git")} "$@"\n').chmod(0o755)
    monkeypatch.setenv("PATH", str(d) + os.pathsep + os.environ["PATH"])
    monkeypatch.setattr(sa, "_GIT_EXE", [])
    r = run(sa.change_set(str(wt), base, **kw))
    assert r["exit_code"] != 0 and "git binary" in r["error"] and "paths" not in r, r
    assert os.path.realpath(wt if where == "checkout" else sa.tempfile.gettempdir()) in r["error"], r


@pytest.mark.parametrize("args", [
    lambda t, p: (t, [], "m"), lambda t, p: (t, [p, p, p], "m"), lambda t, p: (t, ["HEAD"], "m"), lambda t, p: ("HEAD", [p], "m"),
    lambda t, p: (t, [p], ""), lambda t, p: (t, [p], "a\0b"), lambda t, p: (p, [p], "m"), lambda t, p: (t, [t], "m"),
    lambda t, p: (t, [MISSING], "m"), lambda t, p: (t[:12], [p], "m")])
def test_commit_tree_validates_its_inputs(dot, args):
    """1-2 full-sha parents that are commits, a full-sha tree that is a tree, a non-empty message: anything else is an error."""
    _, wt, base = dot
    t, ps, msg = args(_git(wt, "rev-parse", "HEAD^{tree}").strip(), base)
    r = run(_p.commit_tree(str(wt), t, ps, msg))
    assert r["exit_code"] != 0 and r["error"] and "commit" not in r, r


def test_commit_identity_comes_from_the_environment_or_the_global_config_never_the_repository(dot, tmp_path, monkeypatch):
    main, wt, base = dot
    _git(main, "config", "user.name", "Repo Maker")  # a maker can write this: never used
    _git(main, "config", "user.email", "maker@repo")
    tree = _git(wt, "rev-parse", "HEAD^{tree}").strip()
    c = run(_p.commit_tree(str(wt), tree, [base], "m"))["commit"]  # the fixture's env identity (t <t@t>)
    assert "\nauthor t <t@t> " in _git(wt, "cat-file", "commit", c)
    for k in ("GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"):
        monkeypatch.delenv(k)
    r = run(_p.commit_tree(str(wt), tree, [base], "m"))  # GIT_CONFIG_GLOBAL=/dev/null (fixture): git's own fallback, or an error
    assert ("GIT_AUTHOR_NAME" in r["error"]) if r["exit_code"] else "Repo Maker" not in _git(wt, "cat-file", "commit", r["commit"]), r
    g = _w(tmp_path / "global.cfg", '[user]\n\tname = "Global Name" # c\n\temail = g@g\n[alias]\n\tx = !f() { \\\n\techo; }; f\n')
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(g))
    c = run(_p.commit_tree(str(wt), tree, [base], "m"))["commit"]
    body = _git(wt, "cat-file", "commit", c)
    assert "\nauthor Global Name <g@g> " in body and "\ncommitter Global Name <g@g> " in body and "Repo Maker" not in body, body


def test_config_parser_values_and_strictness():
    v = sa._config_values('[core]\n\tbare = false\n[remote "a b\\"c"]\n\turl = "x y" ; c\n[Sec.Sub]\nKey\n# c\n; c\n'
                          '[x] k = 1\n[y]\n\tv = a\\\n\tb\n')
    assert v == {"core.bare": "false", 'remote.a b"c.url': "x y", "sec.sub.key": "true", "x.k": "1", "y.v": "a\tb"}, v
    for bad in ("k = v\n", "[core\n", "[core]\n\t= v\n", '[core]\n\tk = "open\n', "[core]\n\tk = a\\q\n"):
        with pytest.raises(ValueError):
            sa._config_values(bad)
        sa._config_values(bad, strict=False)  # lenient mode (the user's global config): skipped, never raises


def test_locate_is_python_only_and_pins_the_layout(dot, tmp_path, monkeypatch):
    """`_locate` runs no git at all (it used to run `rev-parse` in the target repository) and refuses what it cannot pin."""
    main, wt, base = dot
    expect = os.path.realpath(main / ".git")
    real = subprocess.run
    monkeypatch.setattr(sa.subprocess, "run", lambda *a, **k: pytest.fail(f"git ran: {a}"))
    r, err = sa._locate(str(wt), expect)
    assert err is None and (r.top, r.common, r.main) == (str(wt), expect, str(main)) and Path(r.gitdir).parent.name == "worktrees"
    r, err = sa._locate(str(main), expect)
    assert err is None and r.gitdir == r.common == expect
    assert run(sa.tier_b_hits(str(wt), [SWARM_MD], expect_common_dir=expect))["hits"] == [SWARM_MD]  # no git either
    monkeypatch.setattr(sa.subprocess, "run", real)
    _w(main / ".git/commondir", "../elsewhere\n")  # a main checkout whose .git names another common dir
    assert "commondir" in sa._locate(str(main), expect)[1]["error"]


# ---- T6c attempt 13: where a symlink points depends on where the tree is checked out ---------------------------------------
# Layout (`dot`): main = H/go/src/github.com/kpango/dotfiles, prime worktrees two levels deeper under
# H/go/src/github.com/kpango/.worktrees/dotfiles/ (`mission`: under $SWARM_WORKTREE_DIR = <tmp>/wts). Each link below is harmless
# where the task/mission worktree sits and names a Tier B file once the tree is the main checkout's ("{main}" = its absolute path).
_TO_MAIN = {
    "up-one": ({"x": "../dotfiles/.claude/settings.json"}, ".claude/settings.json"),
    "up-two": ({"agent/x": "../../dotfiles/.claude/settings.json"}, ".claude/settings.json"),
    "up-two-by-parent-name": ({"x": "../../kpango/dotfiles/.claude/settings.local.json"}, ".claude/settings.local.json"),
    "absolute": ({"x": "{main}/.claude/settings.json"}, ".claude/settings.json"),
    "through-dir-symlink": ({"agent/skills/X": "../../../dotfiles/.claude", "y": "agent/skills/X/settings.json"},
                            ".claude/settings.json"),
}
_HARMLESS = {
    "up-one": {"x": "../dotfiles/README.md"},
    "climbs-out": {"x": "../../../../../../nowhere-a13/f"},
    "absolute": {"x": "/nonexistent-a13/f"},
    "through-dir-symlink": {"agent/skills/X": "../../../dotfiles/src", "y": "agent/skills/X/a.go"},
}


def _links(wt, links: dict[str, str], main) -> list[str]:
    """Create `links` as real symlinks in the working tree of `wt` (what a maker leaves); returns their paths."""
    for path, target in links.items():
        (wt / path).parent.mkdir(parents=True, exist_ok=True)
        os.symlink(target.replace("{main}", str(main)), wt / path)
    return sorted(links)


def _commit_links(wt, links: dict[str, str], main) -> None:
    paths = _links(wt, links, main)
    _git(wt, "add", "--", *paths)
    _git(wt, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "links")


def _task(request, layout: str) -> tuple:
    """(main, task worktree, its base): the `dot` worktree, or the task worktree allocated from the `mission` worktree."""
    if layout == "dot":
        return request.getfixturevalue("dot")
    main, _, t, _ = request.getfixturevalue("mission")
    return main, t, _git(t, "rev-parse", "HEAD").strip()


def test_locations_cover_this_checkout_main_registered_worktrees_and_alloc_roots(mission, tmp_path):
    main, m, t, _ = mission
    with _opened(t) as r:
        locs = sa._locations(r)
    w1 = next(p for p in (main.parent / ".worktrees/dotfiles").iterdir())  # the `dot` worktree, registered too
    for want in (t, main, m, w1, main.parent / ".worktrees/dotfiles" / sa._SLOT, (tmp_path / "wts" / sa._SLOT).resolve()):
        assert str(want) in locs, (want, locs)


@pytest.mark.parametrize("layout", ["dot", "mission"])
@pytest.mark.parametrize("case", sorted(_TO_MAIN))
def test_stage_task_refuses_a_link_that_is_tier_b_from_the_main_checkout(request, layout, case):
    """T6c a12 Checker: the target was resolved from the task worktree only, so these passed stage_task with exit 0."""
    main, wt, base = _task(request, layout)
    links, want = _TO_MAIN[case]
    _links(wt, links, main)
    r = run(_p.stage_task(str(wt), base))
    if case == "absolute":  # control: the link's own realpath on disk already is main's file (the pre-check, old code too)
        want = "x"
    assert r["exit_code"] == 3 and want in r["tier_b"] and "tree" not in r, r
    assert _index_names(wt) == ""


@pytest.mark.parametrize("layout", ["dot", "mission"])
@pytest.mark.parametrize("case", sorted(_HARMLESS))
def test_stage_task_passes_a_link_that_is_harmless_from_every_location(request, layout, case):
    main, wt, base = _task(request, layout)
    paths = _links(wt, _HARMLESS[case], main)
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["tier_b"] == [] and r["staged"] == paths, r


@pytest.mark.parametrize("spell", ["absolute", "relative-sibling"])
def test_stage_task_refuses_a_link_into_the_mission_worktree(mission, spell):
    """A target inside ANOTHER checkout of the repository is resolved there (its twin): the mission worktree's own
    .claude/settings.json is the main checkout's once merged, although its absolute path matches no fixed pattern."""
    main, m, t, _ = mission
    target = str(m / ".claude/settings.json") if spell == "absolute" else f"../{m.name}/.claude/settings.json"
    assert not sa._tier_b_match(_rules(), str(m / ".claude/settings.json"), os.environ["HOME"])
    _links(t, {"x": target}, main)
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 3 and ".claude/settings.json" in r["tier_b"], r


@pytest.mark.parametrize("via", ["relative-from-another-depth", "realpath-through-an-outside-symlink"])
def test_stage_task_resolves_a_target_again_inside_the_checkout_it_lands_in(mission, tmp_path, via):
    """The twin re-walk: the `dot` worktree (8 levels below <tmp>) and the mission worktree (2 levels) sit at different depths, so
    resolving the same link from the mission worktree does not land there; and a target reached only through a symlink OUTSIDE
    the tree (`<tmp>/alias -> mission`) lands there only as realpath. Either way it is the mission's .claude/settings.json."""
    main, m, _, _ = mission
    w = next((main.parent / ".worktrees/dotfiles").iterdir())  # the `dot` task worktree
    if via == "realpath-through-an-outside-symlink":
        (tmp_path / "alias").symlink_to(m)
        target = str(tmp_path / "alias/.claude/settings.json")
    else:
        assert len(w.relative_to(tmp_path).parts) == 8, w
        target = "../" * 8 + f"wts/{m.name}/.claude/settings.json"
    _links(w, {"x": target}, main)
    assert os.path.realpath(w / "x") == str(m / ".claude/settings.json")  # on disk: the mission's file, no fixed pattern
    r = run(_p.stage_task(str(w), _git(w, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 3 and ".claude/settings.json" in r["tier_b"], r


@pytest.mark.parametrize("case", sorted(_TO_MAIN))
def test_incoming_and_verify_merge_refuse_a_link_that_is_tier_b_from_the_main_checkout(mission, case):
    """The Checker's full flow: incoming(mission) + tier_b_hits(mission) and verify_merge(mission) all passed (exit 0)."""
    main, m, t, br = mission
    links, want = _TO_MAIN[case]
    _commit_links(t, links, main)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and want in inc["paths"], inc
    tb = run(_p.tier_b_hits(str(m), inc["paths"]))
    assert tb["exit_code"] == 0 and want in tb["hits"], tb
    _merge(m, inc["sha"])  # the test's own merge (what a caller ignoring incoming would get)
    vm = run(_p.verify_merge(str(m), inc["head"]))
    assert vm["exit_code"] == 3 and want in vm["tier_b"], vm


@pytest.mark.parametrize("case", sorted(_HARMLESS))
def test_incoming_and_verify_merge_pass_a_harmless_link(mission, case):
    main, m, t, br = mission
    _commit_links(t, _HARMLESS[case], main)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and run(_p.tier_b_hits(str(m), inc["paths"]))["hits"] == [], inc
    _merge(m, inc["sha"])
    vm = run(_p.verify_merge(str(m), inc["head"]))
    assert vm["exit_code"] == 0 and vm["tier_b"] == [], vm


def test_skill_merge_block_stops_on_a_tier_b_hit_before_writing_anything(mission):
    """SKILL.md's merge block, verbatim: its tier_b_hits call refuses incoming's paths (here: a link that is Tier B only from the
    main checkout) and nothing is written: no commit made, the mission HEAD, index and working tree unchanged."""
    main, m, t, br = mission
    _commit_links(t, _TO_MAIN["up-one"][0], main)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0, inc
    _, merge = _doc_blocks()
    state = (_git(m, "rev-parse", "HEAD"), _git(m, "status", "--porcelain"), _git(m, "ls-files", "-s"))
    with pytest.raises(RuntimeError, match=r"STOP: tier_b_hits: .*\.claude/settings\.json"):
        _run_doc(merge, mission_wt=str(m), inc=inc, msg="merge", cd=_Pinned._kw(m)["expect_common_dir"])
    assert (_git(m, "rev-parse", "HEAD"), _git(m, "status", "--porcelain"), _git(m, "ls-files", "-s")) == state


@pytest.mark.parametrize("how", ["rules-unusable", "error-without-hits"])
def test_skill_merge_block_stops_when_tier_b_hits_fails(mission, monkeypatch, how):
    """exit_code != 0 alone stops the block (also with an empty `hits`): the check failing is never read as "clean"."""
    _, m, t, br = mission
    _w(t / "src/t.go")
    _commit(t, "src/t.go")
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0, inc
    if how == "rules-unusable":
        monkeypatch.setattr(sa, "_write_scope_rules", lambda: (None, None, "rules gone"))
    else:
        async def failing(*a, **k):
            return {"hits": [], "rules": None, "exit_code": 1, "error": "boom"}
        monkeypatch.setattr(sa, "tier_b_hits", failing)
    _, merge = _doc_blocks()
    head = _git(m, "rev-parse", "HEAD")
    with pytest.raises(RuntimeError, match="STOP: tier_b_hits"):
        _run_doc(merge, mission_wt=str(m), inc=inc, msg="merge", cd=_Pinned._kw(m)["expect_common_dir"])
    assert _git(m, "rev-parse", "HEAD") == head


# ---- T6c attempt 14: a link through a symlink on disk OUTSIDE the repository, then `..` ---------------------------------------
# `make claude/install` creates ~/.claude/skills -> <dotfiles>/agent/skills. From the main checkout (5 levels below HOME),
# `../../../../../.claude/skills/..` is <main>/agent for the kernel (`..` after a symlink is the parent of its TARGET); collapsing
# `..` as text made it ~/.claude, and stage_task, incoming + tier_b_hits and verify_merge all passed (T6c a13 Checker).
_UP = "../" * 5  # the main checkout's top level -> HOME
_VIA_OUTSIDE = {
    "skills-dotdot": ({"x": _UP + ".claude/skills/../write-scope-rules.json"}, "agent/write-scope-rules.json"),
    "skills-dotdot-hook": ({"x": _UP + ".claude/skills/../scripts/hooks/decide.py"}, "agent/scripts/hooks/decide.py"),
    "outside-chain": ({"x": _UP + "l1/../../write-scope-rules.json"}, "agent/write-scope-rules.json"),  # ~/l1 -> ~/l2 -> main
    "missing-element": ({"x": _UP + ".claude/nope/../skills/../write-scope-rules.json"}, "agent/write-scope-rules.json"),
    "back-into-a-tree-link": ({"agent/skills/L": "../../.claude", "x": _UP + ".claude/skills/L/settings.json"},
                              ".claude/settings.json"),
}
_HARMLESS_OUTSIDE = {
    "skills-dotdot": {"x": _UP + ".claude/skills/../README.md"},
    "outside-link-elsewhere": {"x": _UP + "elsewhere/../f"},
}


def _outside_links(main, tmp_path) -> None:
    """The disk outside the repository (fake HOME and tmp_path only) that the cases above go through."""
    home = Path(os.environ["HOME"])
    (main / "agent/skills/inner").mkdir(parents=True)  # empty directories: nothing git tracks
    (tmp_path / "ext/d").mkdir(parents=True)
    (home / ".claude").mkdir()
    (home / ".claude/skills").symlink_to(main / "agent/skills")  # what make claude/install creates
    (home / "l1").symlink_to("l2/inner")
    (home / "l2").symlink_to(main / "agent/skills")
    (home / "loop1").symlink_to("loop2")
    (home / "loop2").symlink_to("loop1")
    (home / "elsewhere").symlink_to(tmp_path / "ext/d")


@pytest.mark.parametrize("layout", ["dot", "mission"])
@pytest.mark.parametrize("case", sorted(_VIA_OUTSIDE))
def test_stage_task_resolves_an_outside_symlink_before_the_dotdot_after_it(request, tmp_path, layout, case):
    main, wt, base = _task(request, layout)
    _outside_links(main, tmp_path)
    links, want = _VIA_OUTSIDE[case]
    _links(wt, links, main)
    assert run(_p.tier_b_hits(str(wt), sorted(links)))["hits"] == []  # harmless on the task worktree's own disk
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 3 and want in r["tier_b"] and "tree" not in r, r
    assert _index_names(wt) == ""


@pytest.mark.parametrize("layout", ["dot", "mission"])
@pytest.mark.parametrize("case", sorted(_HARMLESS_OUTSIDE))
def test_stage_task_passes_a_harmless_link_through_an_outside_symlink(request, tmp_path, layout, case):
    main, wt, base = _task(request, layout)
    _outside_links(main, tmp_path)
    paths = _links(wt, _HARMLESS_OUTSIDE[case], main)
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["tier_b"] == [] and r["staged"] == paths, r


@pytest.mark.parametrize("layout", ["dot", "mission"])
def test_stage_task_refuses_an_outside_symlink_loop(request, tmp_path, layout):
    main, wt, base = _task(request, layout)
    _outside_links(main, tmp_path)
    _links(wt, {"x": _UP + "loop1/f"}, main)
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 1 and "too deep" in r["error"] and "tree" not in r, r
    assert _index_names(wt) == ""


@pytest.mark.parametrize("case", sorted(_VIA_OUTSIDE))
def test_incoming_and_verify_merge_resolve_an_outside_symlink_before_the_dotdot_after_it(mission, tmp_path, case):
    main, m, t, br = mission
    _outside_links(main, tmp_path)
    links, want = _VIA_OUTSIDE[case]
    _commit_links(t, links, main)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and want in inc["paths"], inc
    tb = run(_p.tier_b_hits(str(m), inc["paths"]))
    assert tb["exit_code"] == 0 and want in tb["hits"], tb
    _merge(m, inc["sha"])
    vm = run(_p.verify_merge(str(m), inc["head"]))
    assert vm["exit_code"] == 3 and want in vm["tier_b"], vm
    # what the refusal stands for: once the tree reaches the main checkout, `x` IS that Tier B file (`..` after a link resolved
    # physically; "missing-element": once ~/.claude/nope exists)
    (Path(os.environ["HOME"]) / ".claude/nope").mkdir()
    _git(main, "merge", "-q", "--ff-only", _git(m, "rev-parse", "HEAD").strip())
    assert os.path.realpath(main / "x") == os.path.realpath(main / want)


def test_incoming_and_verify_merge_refuse_an_outside_symlink_loop(mission, tmp_path):
    main, m, t, br = mission
    _outside_links(main, tmp_path)
    _commit_links(t, {"x": _UP + "loop1/f"}, main)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 1 and "too deep" in inc["error"] and "paths" not in inc, inc
    head = _git(m, "rev-parse", "HEAD").strip()
    _merge(m, _git(t, "rev-parse", "HEAD").strip())
    vm = run(_p.verify_merge(str(m), head))
    assert vm["exit_code"] == 1 and "too deep" in vm["error"], vm


@pytest.mark.parametrize("case", sorted(_HARMLESS_OUTSIDE))
def test_incoming_and_verify_merge_pass_a_harmless_link_through_an_outside_symlink(mission, tmp_path, case):
    main, m, t, br = mission
    _outside_links(main, tmp_path)
    _commit_links(t, _HARMLESS_OUTSIDE[case], main)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and run(_p.tier_b_hits(str(m), inc["paths"]))["hits"] == [], inc
    _merge(m, inc["sha"])
    vm = run(_p.verify_merge(str(m), inc["head"]))
    assert vm["exit_code"] == 0 and vm["tier_b"] == [], vm


# ---- T6c attempt 15: links through a process-dependent file system; every link again when a symlink changes --------------------
# /proc/self, /proc/thread-self, /proc/<pid>, /dev/fd, /dev/stdin ... are resolved by the kernel FOR THE PROCESS THAT LOOKS: what
# the adapter reads there is only its own view (T6c a14 Checker: `x -> /proc/self/cwd/../dotfiles/.claude/settings.json` passed
# every check with the adapter's cwd anywhere, and named main's settings.json for a process whose cwd is the main checkout).
_PROC = {
    "proc-self-cwd-up": "/proc/self/cwd/../dotfiles/.claude/settings.json",
    "proc-self-cwd": "/proc/self/cwd/.claude/settings.json",
    "proc-thread-self": "/proc/thread-self/cwd/.claude/settings.json",
    "proc-adapter-pid-root": "/proc/{pid}/root{main}/.claude/settings.json",
    "proc-adapter-pid-cwd": "/proc/{pid}/cwd/.claude/settings.json",
    "dev-fd": "/dev/fd/0",
    "dev-stdin": "/dev/stdin",
    "dev-fd-dir": "/dev/fd/3/.claude/settings.json",
    "relative-climb-into-proc": "../" * 40 + "proc/self/cwd/.claude/settings.json",
    "double-slash": "//proc/self/cwd/.claude/settings.json",
    "via-outside-symlink": "{home}/pc/.claude/settings.json",  # ~/pc -> /proc/self/cwd: the TARGET string read from disk
    "via-outside-dir-symlink": "{home}/pd/self/cwd/.claude/settings.json",  # ~/pd -> /proc
}


def _proc_target(case: str, main) -> str:
    home = os.environ["HOME"]
    Path(home, "pc").symlink_to("/proc/self/cwd")
    Path(home, "pd").symlink_to("/proc")
    return _PROC[case].format(pid=os.getpid(), main=main, home=home)


def _adapter_cwd(monkeypatch, where: str, main, m, tmp_path) -> None:
    monkeypatch.chdir({"main": main, "mission": m, "outside": tmp_path}[where])


@pytest.mark.parametrize("how", ["worktree", "index"])
@pytest.mark.parametrize("where", ["main", "mission", "outside"])
@pytest.mark.parametrize("case", sorted(_PROC))
def test_stage_task_refuses_a_link_through_a_process_dependent_file_system(mission, monkeypatch, tmp_path, where, case, how):
    main, m, t, _ = mission
    _adapter_cwd(monkeypatch, where, main, m, tmp_path)
    target = _proc_target(case, main)
    if how == "worktree":
        _links(t, {"x": target}, main)
    else:  # index-injected: the working tree has no link, so only the walk of the verified tree can refuse it
        _w(t / "src/new.go")
        _inject_on_first_write_tree(monkeypatch, lambda: _inject_link(t, "x", target))
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    # worktree: 3 when the working-tree pre-check already hits in THIS process's view (e.g. cwd = main), else the walk refuses it
    assert r["exit_code"] in ((1, 3) if how == "worktree" else (1,)) and "tree" not in r, r
    if r["exit_code"] == 1:
        assert "special file system" in r["error"], r
    assert _index_names(t) == ""


@pytest.mark.parametrize("where", ["main", "mission", "outside"])
@pytest.mark.parametrize("case", sorted(_PROC))
def test_incoming_and_verify_merge_refuse_a_link_through_a_process_dependent_file_system(mission, monkeypatch, tmp_path, where,
                                                                                          case):
    main, m, t, br = mission
    _adapter_cwd(monkeypatch, where, main, m, tmp_path)
    _commit_links(t, {"x": _proc_target(case, main)}, main)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 1 and "special file system" in inc["error"] and "paths" not in inc, inc
    head = _git(m, "rev-parse", "HEAD").strip()
    _merge(m, _git(t, "rev-parse", "HEAD").strip())
    vm = run(_p.verify_merge(str(m), head))
    assert vm["exit_code"] == 1 and "special file system" in vm["error"], vm


def test_special_devs_are_read_from_mountinfo():
    devs = sa._special_devs()
    assert os.lstat("/proc").st_dev in devs and os.lstat("/sys").st_dev in devs
    assert os.lstat(os.environ["HOME"]).st_dev not in devs


@pytest.mark.parametrize("special", [True, False])
def test_a_link_into_a_special_mount_found_by_st_dev_is_refused(mission, monkeypatch, tmp_path, special):
    """(b) of the rule: a proc/sysfs/... mount at a path no prefix names (a bind mount of /proc elsewhere) is found by st_dev. The
    test stands one in for <tmp>/ext's file system; negative control: the same link with the real special devices passes."""
    main, m, t, br = mission
    _w(tmp_path / "ext/f")
    if special:
        monkeypatch.setattr(sa, "_special_devs", lambda: frozenset({os.lstat(tmp_path / "ext").st_dev}))
    _links(t, {"x": str(tmp_path / "ext/f")}, main)
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    if special:
        assert r["exit_code"] == 1 and "special file system" in r["error"] and _index_names(t) == "", r
    else:
        assert r["exit_code"] == 0 and r["tier_b"] == [] and r["staged"] == ["x"], r


# A symlink the diff does NOT add can change where it points when the diff changes ANOTHER symlink (or swaps a directory and a
# symlink) that its path goes through (T6c a14 Checker observation): every symlink of the final tree is resolved again then.
# Each case: (base files, base links, the task's change, the path that becomes Tier B or None = harmless).
_RELINK = {
    "dir-to-symlink": ({"d/keep.txt"}, {"y": "d/write-scope-rules.json"}, ("rmdir", "d", "agent"), "agent/write-scope-rules.json"),
    "symlink-retarget": ({"other/keep.txt"}, {"d": "other", "y": "d/write-scope-rules.json"}, ("relink", "d", "agent"),
                         "agent/write-scope-rules.json"),
    "symlink-to-dir": ({"x/y/keep.txt"}, {"agent/d": "../x/y", "y": "agent/d/../write-scope-rules.json"}, ("mkdir", "agent/d", None),
                       "agent/write-scope-rules.json"),
    "harmless-retarget": ({"other/keep.txt", "src/b.txt"}, {"d": "other", "y": "d/write-scope-rules.json"}, ("relink", "d", "src"),
                          None),
    "harmless-dir-to-symlink": ({"d/keep.txt"}, {"y": "d/write-scope-rules.json"}, ("rmdir", "d", "src"), None),
}


def _relink_base(main, monkeypatch, tmp_path, case: str) -> tuple:
    """Commit the case's base files and links in main, then allocate (mission, task) from it: the links are in the task's base."""
    files, links, _, _ = _RELINK[case]
    for f in files:
        _w(main / f)
    _git(main, "add", "--", *files)
    _commit_links(main, links, main)
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wts2"))
    m = Path(run(sa.worktree_alloc("mission2", cwd=str(main)))["path"])
    t = run(sa.worktree_alloc("task2", cwd=str(m)))
    return m, Path(t["path"]), t["branch"]


def _relink(wt, case: str) -> None:
    how, path, target = _RELINK[case][2]
    p = wt / path
    if how == "rmdir":
        shutil.rmtree(p)
        p.symlink_to(target)
    elif how == "relink":
        p.unlink()
        p.symlink_to(target)
    else:
        p.unlink()
        _w(p / "f")


@pytest.mark.parametrize("case", sorted(_RELINK))
def test_stage_task_resolves_every_link_again_when_a_symlink_changes(dot, monkeypatch, tmp_path, case):
    main, _, _ = dot
    _, t, _ = _relink_base(main, monkeypatch, tmp_path, case)
    _relink(t, case)
    want = _RELINK[case][3]
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    if want:
        assert r["exit_code"] == 3 and want in r["tier_b"] and "tree" not in r, r
        assert _index_names(t) == ""
        assert os.path.realpath(t / "y") == str(t / want)  # what the refusal stands for: the UNCHANGED link y now is that path
    else:
        assert r["exit_code"] == 0 and r["tier_b"] == [], r


@pytest.mark.parametrize("case", sorted(_RELINK))
def test_incoming_and_verify_merge_resolve_every_link_again_when_a_symlink_changes(dot, monkeypatch, tmp_path, case):
    main, _, _ = dot
    m, t, br = _relink_base(main, monkeypatch, tmp_path, case)
    _relink(t, case)
    _git(t, "add", "-A")
    _git(t, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "relink")
    want = _RELINK[case][3]
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0, inc
    hits = run(_p.tier_b_hits(str(m), inc["paths"]))["hits"]
    _merge(m, inc["sha"])
    vm = run(_p.verify_merge(str(m), inc["head"]))
    if want:
        assert want in inc["paths"] and want in hits, (inc, hits)
        assert vm["exit_code"] == 3 and want in vm["tier_b"], vm
    else:
        assert hits == [] and vm["exit_code"] == 0 and vm["tier_b"] == [], (inc, hits, vm)


def test_a_diff_without_a_symlink_change_does_not_resolve_the_unchanged_links(dot, monkeypatch, tmp_path):
    """The re-walk is tied to a symlink change: a plain file change leaves the base's links alone (they were checked when added)."""
    main, _, _ = dot
    _, t, _ = _relink_base(main, monkeypatch, tmp_path, "harmless-retarget")
    _w(t / "src/new.go")
    calls = []
    real = sa._link_final
    monkeypatch.setattr(sa, "_link_final", lambda *a, **k: calls.append(a) or real(*a, **k))
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 0 and r["staged"] == ["src/new.go"] and calls == [], r


@pytest.mark.parametrize("cap", ["_MAX_LINKS", "_MAX_TOTAL_HOPS"])
def test_link_resolution_cost_is_capped(dot, monkeypatch, tmp_path, cap):
    main, _, _ = dot
    _, t, _ = _relink_base(main, monkeypatch, tmp_path, "harmless-retarget")
    _relink(t, "harmless-retarget")  # d -> src: harmless, and under the limits as shipped (the case above passes)
    monkeypatch.setattr(sa, cap, 1)
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 1 and ("too many symlinks" if cap == "_MAX_LINKS" else "budget") in r["error"], r
    assert _index_names(t) == ""


# ---- T6c attempt 16: the disk INSIDE a checkout location, tree/disk disagreement, and the registrations behind the locations ------
# a15 Checker: once a walk entered a location (`_locations`) it went on by the tree only, so an untracked / ignored disk symlink
# there was never read; the path then went to os.path.realpath, which answers /proc/self/cwd for the ADAPTER's cwd; and writing
# `<common>/worktrees/<n>/gitdir` made any directory a location. With the adapter's cwd outside every location stage_task,
# incoming + tier_b_hits and verify_merge all passed, and the merged `x` named main's .claude/settings.json (or
# agent/write-scope-rules.json) for a process whose cwd is the main checkout (or main/agent).
_A16 = ("ignored-proc-dir", "ignored-proc-cwd", "forged-registration")
_REFUSED = "special file system|forged or broken"


def _commit_kept(wt, *paths) -> None:
    """Commit without git's auto maintenance: measured, `git commit` starts a detached `git maintenance run --auto` that prunes a
    worktree registration without HEAD, possibly AFTER the commit returned (a forged entry would vanish under the test)."""
    _git(wt, "add", "--", *paths)
    _git(wt, "-c", "maintenance.auto=false", "-c", "gc.auto=0", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "c")


def _a16_plant(case: str, main, t, tmp_path) -> dict[str, str]:
    """Plant the case's disk state (the maker's own task worktree, or the shared git dir); returns the link(s) it commits."""
    if case == "forged-registration":  # the Checker's (2): a registration with only `gitdir`, for a directory the maker owns
        ev = tmp_path / "evil"
        ev.mkdir()
        _w(main / ".git/worktrees/fake/gitdir", f"{ev}/.git\n")
        (ev / "s").symlink_to("/proc/self/cwd/.claude")
        return {"x": f"{ev}/s/settings.json"}
    target, leaf = {"ignored-proc-dir": ("/proc/self/cwd/.claude", "settings.json"),  # (1)
                    "ignored-proc-cwd": ("/proc/self/cwd", "write-scope-rules.json")}[case]  # (3)
    _w(t / ".gitignore", "ig/\n")
    (t / "ig").mkdir()
    (t / "ig/s").symlink_to(target)
    return {"x": f"{t}/ig/s/{leaf}"}


@pytest.mark.parametrize("how", ["worktree", "index"])
@pytest.mark.parametrize("where", ["main", "mission", "outside"])
@pytest.mark.parametrize("case", _A16)
def test_stage_task_refuses_a_link_through_the_disk_inside_a_location(mission, monkeypatch, tmp_path, where, case, how):
    main, m, t, _ = mission
    _adapter_cwd(monkeypatch, where, main, m, tmp_path)
    links = _a16_plant(case, main, t, tmp_path)
    if how == "worktree":
        _links(t, links, main)
    else:  # index-injected: no `x` in the working tree, only the walk of the verified tree sees it
        _w(t / "src/new.go")
        _inject_on_first_write_tree(monkeypatch, lambda: [_inject_link(t, k, v) for k, v in links.items()])
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 1 and re.search(_REFUSED, r["error"]) and "tree" not in r, r
    assert _index_names(t) == ""


@pytest.mark.parametrize("where", ["main", "mission", "outside"])
@pytest.mark.parametrize("case", _A16)
def test_incoming_and_verify_merge_refuse_a_link_through_the_disk_inside_a_location(mission, monkeypatch, tmp_path, where,
                                                                                     case):
    main, m, t, br = mission
    _adapter_cwd(monkeypatch, where, main, m, tmp_path)
    links = _a16_plant(case, main, t, tmp_path)
    _links(t, links, main)
    _commit_kept(t, *links, *([".gitignore"] if (t / ".gitignore").exists() else []))  # past stage_task; ig/s stays (ignored)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 1 and re.search(_REFUSED, inc["error"]) and "paths" not in inc, inc
    # the SKILL.md merge block's next call, with what a15's incoming reported: the target path itself is refused on disk
    tb = run(_p.tier_b_hits(str(m), [*links.values(), *links]))
    assert tb["exit_code"] == 1 and "special file system" in tb["error"], tb
    head = _git(m, "rev-parse", "HEAD").strip()
    _merge(m, _git(t, "rev-parse", "HEAD").strip())
    vm = run(_p.verify_merge(str(m), head))
    assert vm["exit_code"] == 1 and re.search(_REFUSED, vm["error"]), vm


@pytest.mark.parametrize("where", ["main", "mission", "outside"])
def test_stage_task_refuses_a_relative_link_through_an_ignored_symlink_in_the_mission_worktree(mission, monkeypatch, tmp_path,
                                                                                             where):
    """The walk with the tree checked out at the MISSION worktree reads the disk there where the tree has nothing: the mission's
    untracked (ignored once `.gitignore` is merged) `ig/s -> /proc/self/cwd/.claude` stays after the merge, and
    `x -> ig/s/settings.json` is then main's settings.json for a process whose cwd is the main checkout. tier_b_hits' disk view
    covers the task and main checkouts only, so only the walk sees it (a15: `ig` was a plain name inside a location, exit 0)."""
    main, m, t, _ = mission
    _adapter_cwd(monkeypatch, where, main, m, tmp_path)
    (m / "ig").mkdir()
    (m / "ig/s").symlink_to("/proc/self/cwd/.claude")
    _w(t / ".gitignore", "ig/\n")
    _links(t, {"x": "ig/s/settings.json"}, main)
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 1 and "special file system" in r["error"] and "tree" not in r, r
    assert _index_names(t) == ""


_A16_HARMLESS = {  # an ignored disk symlink inside the task worktree that stays harmless: no refusal
    "ignored-into-the-tree": ({"ig/s": "../src"}, {"x": "ig/s/a.go"}),
    "ignored-outside": ({"ig/s": "{tmp}/exth"}, {"x": "{t}/ig/s/f"}),
}


@pytest.mark.parametrize("case", sorted(_A16_HARMLESS))
def test_a_harmless_ignored_symlink_inside_a_location_passes(mission, tmp_path, case):
    main, m, t, br = mission
    disk, links = ({k: v.replace("{tmp}", str(tmp_path)).replace("{t}", str(t)) for k, v in d.items()} for d in _A16_HARMLESS[case])
    (tmp_path / "exth").mkdir()
    _w(t / ".gitignore", "ig/\n")
    _links(t, disk, main)
    _links(t, links, main)
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 0 and r["tier_b"] == [] and r["staged"] == [".gitignore", "x"], r
    _git(t, "add", ".gitignore", "x")
    _git(t, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "links")
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and run(_p.tier_b_hits(str(m), inc["paths"]))["hits"] == [], inc
    _merge(m, inc["sha"])
    vm = run(_p.verify_merge(str(m), inc["head"]))
    assert vm["exit_code"] == 0 and vm["tier_b"] == [], vm


# Tree and disk DISAGREE inside a location: a local change in the mission worktree, which `read-tree -m -u` and `git merge` keep at
# a path the merge leaves alone. By the tree `x` is harmless; by the disk it goes through <tmp>/ext3/a. Each case: (base files,
# base links, the mission's local change, the task's link).
_SKEW = {
    "dir-is-a-symlink-on-disk": ({"d/keep.txt"}, {}, "d", "d/a"),
    "symlink-retargeted-on-disk": ({"src/b.txt"}, {"l": "src"}, "l", "l/a"),
    "file-is-a-dir-on-disk": ({"f"}, {}, "f", "f/a"),
}
_SKEW_TARGET = {"tier-b": "{main}/.claude/settings.json", "harmless": "/nonexistent-a16/f",
                "proc": "/proc/self/cwd/.claude/settings.json"}


def _skew(main, monkeypatch, tmp_path, case: str, what: str) -> tuple:
    """Commit the case's base in main, allocate (mission, task) from it, make the mission's local change; returns (m, t, branch)."""
    files, links, at, _ = _SKEW[case]
    for f in files:
        _w(main / f)
    _links(main, links, main)
    _git(main, "add", "--", *files, *links)
    _git(main, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base")
    monkeypatch.setenv("SWARM_WORKTREE_DIR", str(tmp_path / "wts3"))
    m = Path(run(sa.worktree_alloc("mission3", cwd=str(main)))["path"])
    t = run(sa.worktree_alloc("task3", cwd=str(m)))
    target = _SKEW_TARGET[what].replace("{main}", str(main))
    ext = tmp_path / "ext3"
    ext.mkdir()
    (ext / "a").symlink_to(target)
    p = m / at
    if case == "file-is-a-dir-on-disk":
        p.unlink()
        p.mkdir()
        (p / "a").symlink_to(target)
    else:
        shutil.rmtree(p) if not p.is_symlink() else p.unlink()
        p.symlink_to(ext)
    return m, Path(t["path"]), t["branch"]


@pytest.mark.parametrize("what", sorted(_SKEW_TARGET))
@pytest.mark.parametrize("case", sorted(_SKEW))
def test_stage_task_checks_both_views_where_tree_and_disk_disagree(dot, monkeypatch, tmp_path, case, what):
    main, _, _ = dot
    m, t, _ = _skew(main, monkeypatch, tmp_path, case, what)
    _links(t, {"x": _SKEW[case][3]}, main)
    assert run(_p.tier_b_hits(str(t), ["x"]))["hits"] == []  # the task worktree's own disk: harmless
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    if what == "tier-b":
        assert r["exit_code"] == 3 and ".claude/settings.json" in r["tier_b"] and "tree" not in r, r
    elif what == "proc":
        assert r["exit_code"] == 1 and "special file system" in r["error"] and "tree" not in r, r
    else:
        assert r["exit_code"] == 0 and r["tier_b"] == [] and r["staged"] == ["x"], r


@pytest.mark.parametrize("what", sorted(_SKEW_TARGET))
@pytest.mark.parametrize("case", sorted(_SKEW))
def test_incoming_and_verify_merge_check_both_views_where_tree_and_disk_disagree(dot, monkeypatch, tmp_path, case, what):
    main, _, _ = dot
    m, t, br = _skew(main, monkeypatch, tmp_path, case, what)
    _commit_links(t, {"x": _SKEW[case][3]}, main)
    inc = run(_p.incoming(str(m), br))
    head = _git(m, "rev-parse", "HEAD").strip()
    # the merge as update_ref(checkout=True) checks it out (`read-tree -m -u`, measured: it keeps the mission's local change at a
    # path the merge leaves alone; `git merge` refuses "beyond a symbolic link" for the directory case), then committed
    _git(m, "read-tree", "-m", "-u", head, _git(t, "rev-parse", "HEAD").strip())
    _git(m, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "merge")
    vm = run(_p.verify_merge(str(m), head))
    if what == "proc":
        assert inc["exit_code"] == 1 and "special file system" in inc["error"], inc
        assert vm["exit_code"] == 1 and "special file system" in vm["error"], vm
        return
    assert inc["exit_code"] == 0, inc
    hits = run(_p.tier_b_hits(str(m), inc["paths"]))["hits"]
    if what == "tier-b":
        assert ".claude/settings.json" in hits and vm["exit_code"] == 3 and ".claude/settings.json" in vm["tier_b"], (inc, hits, vm)
        # what the refusal stands for: after the merge the mission's `x` IS main's settings.json on disk
        assert os.path.realpath(m / "x") == str(main / ".claude/settings.json")
    else:
        assert hits == [] and vm["exit_code"] == 0 and vm["tier_b"] == [], (inc, hits, vm)


def test_link_final_reads_no_disk_below_a_disk_symlink_where_the_tree_has_a_directory(tmp_path):
    """Below `d` (a directory in the tree, a symlink on disk) the tree's walk reads nothing from disk: an lstat of `<top>/d/a`
    would follow the disk's `d` (here to <tmp>/elsewhere, where `a` is a symlink); the disk's view is the fork, walked with `d`
    taken from disk."""
    top = tmp_path / "top"
    (tmp_path / "elsewhere").mkdir()
    (tmp_path / "elsewhere/a").symlink_to(tmp_path / "far")
    top.mkdir()
    (top / "d").symlink_to(tmp_path / "elsewhere")
    tree = {"x": "120000", "d": "040000", "d/k": "100644"}
    args = (str(top), {"x": "oid"}, lambda oid: "d/a/f")
    forks = []
    assert sa._link_final(*args, "x", [str(top)], frozenset(), [100], tree, forks) == "d/a/f"
    assert forks == [(f"{top}/d/a/f", "d")]
    assert sa._link_final(*args, forks[0][0], [str(top)], frozenset(), [100], tree, [], forks[0][1]) == f"{tmp_path}/far/f"


def _forge(main, tmp_path, how: str) -> Path:
    """A registration `<common>/worktrees/fake` for <tmp>/evil, consistent in every file ("consistent"), or broken as `how` says."""
    common, ev = main / ".git", tmp_path / "evil"
    adm = common / "worktrees/fake"
    ev.mkdir()
    if how == "entry-is-a-file":
        _w(adm, "x\n")
        return ev
    if how == "entry-is-a-symlink":
        adm.symlink_to(next(p for p in (common / "worktrees").iterdir()))
        return ev
    _w(adm / "gitdir", f"{ev}/.git\n")
    if how == "gitdir-only":
        return ev
    _w(adm / "commondir", "../..\n" if how != "commondir-elsewhere" else f"{tmp_path}\n")
    if how != "no-head":
        _w(adm / "HEAD", "ref: refs/heads/main\n")
    other = next(p for p in (common / "worktrees").iterdir() if p.name != "fake")
    _w(ev / ".git", f"gitdir: {other if how == 'gitfile-names-another-admin-dir' else adm}\n")
    if how == "worktree-is-a-symlink":
        (tmp_path / "alias").symlink_to(ev)
        _w(adm / "gitdir", f"{tmp_path}/alias/.git\n")
    if how == "not-dot-git":
        _w(adm / "gitdir", f"{ev}/notgit\n")
    return ev


_FORGED = ("gitdir-only", "no-head", "commondir-elsewhere", "gitfile-names-another-admin-dir", "worktree-is-a-symlink",
           "entry-is-a-symlink", "entry-is-a-file", "not-dot-git")


@pytest.mark.parametrize("how", _FORGED)
def test_a_forged_or_broken_worktree_registration_is_an_error(mission, tmp_path, how):
    main, m, t, br = mission
    _forge(main, tmp_path, how)
    with _opened(t) as r, pytest.raises(RuntimeError, match="forged or broken"):
        sa._locations(r)
    _links(t, {"y": "src/a.go"}, main)  # a harmless symlink: the diff touches one, so the locations are needed
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 1 and "forged or broken" in r["error"] and "tree" not in r, r
    _links(t, {"z": "src/a.go"}, main)
    _commit_kept(t, "z")
    assert (main / ".git/worktrees/fake").exists()
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 1 and "forged or broken" in inc["error"], inc


def test_a_consistent_registration_is_kept_and_its_disk_still_refused(mission, tmp_path):
    """A registration forged in every file IS a worktree to git: it is a location, which only adds the tree's view there; the
    disk is still read (the Checker's link through it is refused)."""
    main, m, t, br = mission
    ev = _forge(main, tmp_path, "consistent")
    with _opened(t) as r:
        assert str(ev) in sa._locations(r)
    (ev / "s").symlink_to("/proc/self/cwd/.claude")
    _links(t, {"x": f"{ev}/s/settings.json"}, main)
    _commit_kept(t, "x")
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 1 and "special file system" in inc["error"], inc


def test_a_prunable_or_gitdir_less_registration_is_no_error(mission, tmp_path):
    """git's own stale states: a worktree deleted by hand (its `.git` gone, the admin dir kept: "prunable") stays a location; an
    admin dir without `gitdir` registers nothing."""
    main, m, t, br = mission
    w1 = next((main.parent / ".worktrees/dotfiles").iterdir())  # the `dot` task worktree
    shutil.rmtree(w1)
    (main / ".git/worktrees/empty").mkdir()
    with _opened(t) as r:
        assert str(w1) in sa._locations(r)
    _links(t, {"y": "src/a.go"}, main)
    r = run(_p.stage_task(str(t), _git(t, "rev-parse", "HEAD").strip()))
    assert r["exit_code"] == 0 and r["staged"] == ["y"], r


@pytest.mark.parametrize("rel", [".claude/skills/../x", "l1/../../f", "nope/../f", "elsewhere/../f", "elsewhere/./g",
                                 "loop1/f", ".claude/skills/inner"])
def test_real_is_realpath_without_the_process_dependent_answers(dot, tmp_path, rel):
    main, _, _ = dot
    _outside_links(main, tmp_path)
    p = os.environ["HOME"] + "/" + rel
    if rel.startswith("loop"):
        with pytest.raises(RuntimeError, match="too deep"):
            sa._real(p, sa._special_devs())
    else:
        assert sa._real(p, sa._special_devs()) == os.path.realpath(p)


@pytest.mark.parametrize("p", ["/proc/self/cwd/x", "//proc/./self", "/dev/fd/0", "/sys", "{home}/pc/.claude", "{home}/pd/self"])
def test_real_and_tier_b_hits_refuse_a_process_dependent_path(dot, p):
    main, wt, _ = dot
    home = os.environ["HOME"]
    Path(home, "pc").symlink_to("/proc/self/cwd")
    Path(home, "pd").symlink_to("/proc")
    p = p.format(home=home)
    with pytest.raises(RuntimeError, match="special file system"):
        sa._real(p, sa._special_devs())
    tb = run(_p.tier_b_hits(str(wt), [p, "README.md"]))
    assert tb["exit_code"] == 1 and "special file system" in tb["error"] and tb["hits"] == [p, "README.md"], tb


# ---- T6c a17: a forged object store (loose object, pack, alternates) ----------------------------------------------------------
def _sha_of(typ: str, data: bytes) -> str:
    return hashlib.sha1(b"%s %d\0" % (typ.encode(), len(data)) + data).hexdigest()


def _obj(wt, oid: str) -> Path:
    return _common_dir(wt) / "objects" / oid[:2] / oid[2:]


def _hooks_tree(wt, rev: str) -> str:
    return _git(wt, "rev-parse", f"{rev}:agent/hooks/claude").strip()


def _evil_hooks_tree(wt) -> str:
    """HOOK = EVIL in the working tree and the index (the task's change) and the id of the `agent/hooks/claude` subtree holding it,
    written as a loose object by `write-tree`."""
    _w(wt / HOOK, "EVIL\n")
    _git(wt, "add", "--", HOOK)  # staged, as the maker of the a16 Checker's f2 left it
    return _hooks_tree(wt, _git(wt, "write-tree").strip())


def _forge_object(wt, victim: str, donor: str, how: str = "loose") -> None:
    """Make the shared object store serve the content of loose object `donor` under the id `victim`, as a maker can: `loose` =
    donor's file copied to victim's path (created if absent); `pack` = victim's loose file removed, a pack holding donor whose .idx
    names that entry `victim` (git checks neither the entry's hash nor its CRC when reading); `alt` = victim's loose file removed,
    the forged file placed in a directory listed in objects/info/alternates."""
    v, data = _obj(wt, victim), _obj(wt, donor).read_bytes()
    if how == "loose":
        v.parent.mkdir(exist_ok=True)
        if v.exists():
            v.chmod(0o644)
        v.write_bytes(data)
        return
    v.unlink()
    objects = _common_dir(wt) / "objects"
    if how == "alt":
        alt = Path(os.environ["HOME"]) / "alt-objects"
        (alt / victim[:2]).mkdir(parents=True)
        (alt / victim[:2] / victim[2:]).write_bytes(data)
        (objects / "info").mkdir(exist_ok=True)
        (objects / "info/alternates").write_text(f"{alt}\n")
        return
    h = subprocess.run(["git", "pack-objects", "-q", str(objects / "pack/pack")], cwd=wt, input=donor + "\n", check=True,
                       capture_output=True, text=True).stdout.strip()
    idx = objects / f"pack/pack-{h}.idx"
    b = bytearray(idx.read_bytes())
    assert b[:8] == b"\377tOc\0\0\0\2" and int.from_bytes(b[8 + 255 * 4:8 + 256 * 4], "big") == 1  # v2, one object
    for i in range(256):  # fan-out: objects whose first byte is <= i
        b[8 + i * 4:12 + i * 4] = (int(i >= int(victim[:2], 16))).to_bytes(4, "big")
    assert b[1032:1052] == bytes.fromhex(donor)
    b[1032:1052] = bytes.fromhex(victim)
    _rehash(b, idx)


def _no_rehash(monkeypatch) -> None:
    """Negative control: the primitives without `_verify_objects` (the a16 state for trees, commits and diff blobs)."""
    monkeypatch.setattr(sa, "_verify_objects", lambda *a, **k: "")


@pytest.mark.parametrize("how", ["loose", "pack", "alt"])
def test_stage_task_refuses_a_forged_subtree_of_base(dot, monkeypatch, how):
    """T6c a17 Checker (f2): the maker writes HOOK = EVIL, then makes the store serve that new `agent/hooks/claude` subtree under
    the BASE commit's subtree id. diff-tree / ls-tree -r never hash-check a subtree, so base read as EVIL and the Tier B change
    vanished (stage_task exit 0, staged [], then commit, merge and verify_merge all exit 0). Every tree base and HEAD reach is
    re-hashed first: refused, real index untouched. Same through a forged pack (.idx entry) and an alternates directory."""
    _, wt, base = dot
    _forge_object(wt, _hooks_tree(wt, base), _evil_hooks_tree(wt), how)
    assert _git(wt, "cat-file", "-p", f"{base}:{HOOK}") == "EVIL\n"  # plain git reads the forgery as base's content
    before = _git(wt, "ls-files", "-s")
    for f in (_p.change_set, _p.stage_task):
        r = run(f(str(wt), base))
        assert r["exit_code"] != 0 and "object store forged" in r["error"] and "paths" not in r and "tree" not in r, r
    assert _git(wt, "ls-files", "-s") == before
    _no_rehash(monkeypatch)
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["tier_b"] == [] and r["staged"] == [], r  # blind without the re-hash


def test_incoming_and_tier_b_hits_refuse_a_forged_subtree_of_the_mission_head(mission, monkeypatch):
    """f2 one step later: the task commit carries HOOK = EVIL (honestly), and the mission HEAD's subtree id is made to serve the
    task's subtree: `merge-tree` + `diff-tree head <result>` saw no change, so tier_b_hits(paths) had nothing to hit."""
    _, m, t, br = mission
    head = _git(m, "rev-parse", "HEAD").strip()
    _w(t / HOOK, "EVIL\n")
    _commit(t, HOOK)
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and run(_p.tier_b_hits(str(m), inc["paths"]))["hits"] == [HOOK], inc  # honest store
    _forge_object(m, _hooks_tree(m, head), _hooks_tree(t, "HEAD"))
    r = run(_p.incoming(str(m), br))
    assert r["exit_code"] != 0 and "object store forged" in r["error"] and "paths" not in r, r
    _no_rehash(monkeypatch)
    r = run(_p.incoming(str(m), br))
    assert r["exit_code"] == 0 and HOOK not in r["paths"] and run(_p.tier_b_hits(str(m), r["paths"]))["hits"] == [], r


def test_verify_merge_refuses_a_forged_subtree_of_the_merge_start(mission, monkeypatch):
    """The merge is committed (by any means); then `head`'s subtree id serves the merged subtree: `diff-tree head HEAD` was empty."""
    _, m, t, _ = mission
    head = _git(m, "rev-parse", "HEAD").strip()
    _w(t / HOOK, "EVIL\n")
    _commit(t, HOOK)
    _merge(m, _git(t, "rev-parse", "HEAD").strip())
    assert run(_p.verify_merge(str(m), head))["tier_b"] == [HOOK]  # honest store
    _forge_object(m, _hooks_tree(m, head), _hooks_tree(t, "HEAD"))
    r = run(_p.verify_merge(str(m), head))
    assert r["exit_code"] != 0 and "object store forged" in r["error"] and "paths" not in r, r
    _no_rehash(monkeypatch)
    r = run(_p.verify_merge(str(m), head))
    assert r["exit_code"] == 0 and r["tier_b"] == [] and HOOK not in r["paths"], r


def test_stage_task_refuses_a_preplanted_blob(dot, monkeypatch):
    """A blob forgery: the maker plants other content under the id of a file the task adds BEFORE stage_task writes it
    (`hash-object -w` keeps an object that is already there). The diff entry's blob is re-hashed: refused. Without it the commit
    names that id and plain git reads the planted content, not the file that was checked."""
    _, wt, base = dot
    _w(wt / "src/n.go", "task\n")
    _forge_object(wt, _sha_of("blob", b"task\n"), _blob(wt, "planted\n"))
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] != 0 and "object store forged" in r["error"] and "tree" not in r, r
    _no_rehash(monkeypatch)
    r = run(_p.stage_task(str(wt), base))
    assert r["exit_code"] == 0 and r["staged"] == ["src/n.go"], r
    assert _git(wt, "cat-file", "-p", f"{r['tree']}:src/n.go") == "planted\n"


def test_incoming_refuses_a_forged_symlink_blob(mission, monkeypatch):
    """A symlink blob forgery: the task commits `src/l -> ../agent/hooks/claude/x.sh` (Tier B once resolved) and the store serves
    `a.go` under that blob's id, so the link resolved to src/a.go. Both re-hash layers refuse it: the diff blobs
    (`_verify_objects`) and, with that layer off, the link-text read itself (`_cat`). Without both, the target is harmless."""
    _, m, t, br = mission
    _commit_link(t, "src/l", "../agent/hooks/claude/x.sh")
    inc = run(_p.incoming(str(m), br))
    assert inc["exit_code"] == 0 and HOOK in inc["paths"], inc  # honest store
    _forge_object(t, _blob(t, "../agent/hooks/claude/x.sh"), _blob(t, "a.go"))
    r = run(_p.incoming(str(m), br))
    assert r["exit_code"] != 0 and "object store forged" in r["error"] and "paths" not in r, r
    _no_rehash(monkeypatch)
    r = run(_p.incoming(str(m), br))
    assert r["exit_code"] != 0 and "object store forged" in r["error"] and "paths" not in r, r

    def unchecked(r, want, keep):  # the a16 read: `cat-file <type> <oid>`, no hash check
        return {o: sa._git_b(r, "cat-file", t, o).stdout for o, t in want.items()}

    monkeypatch.setattr(sa, "_cat", unchecked)
    r = run(_p.incoming(str(m), br))
    assert r["exit_code"] == 0 and HOOK not in r["paths"] and "src/a.go" in r["paths"], r


def test_commit_tree_refuses_a_preplanted_commit(dot, monkeypatch):
    """A commit forgery: commit-tree's id is predictable (tree, parents, identity, date), and an object already stored under it is
    kept, so a maker can plant another commit's content there (here one whose tree carries HOOK = EVIL). The written commit is
    re-hashed: refused. Without it commit_tree returns that id with exit 0 (git's own check on a named commit stops update_ref
    later, measured)."""
    _, wt, base = dot
    for k in ("GIT_AUTHOR_DATE", "GIT_COMMITTER_DATE"):
        monkeypatch.setenv(k, "1700000000 +0000")
    tree = _git(wt, "rev-parse", "HEAD^{tree}").strip()
    cid = _sha_of("commit", f"tree {tree}\nparent {base}\nauthor t <t@t> 1700000000 +0000\n"
                            "committer t <t@t> 1700000000 +0000\n\nm\n".encode())
    _w(wt / HOOK, "EVIL\n")
    _git(wt, "add", "--", HOOK)
    evil = _git(wt, "-c", "commit.gpgsign=false", "commit-tree", _git(wt, "write-tree").strip(), "-p", base, "-m", "e").strip()
    _forge_object(wt, cid, evil)
    r = run(_p.commit_tree(str(wt), tree, [base], "m"))
    assert r["exit_code"] != 0 and "object store forged" in r["error"] and "commit" not in r, r
    _no_rehash(monkeypatch)
    r = run(_p.commit_tree(str(wt), tree, [base], "m"))
    assert r["exit_code"] == 0 and r["commit"] == cid, r
    assert _git(wt, "cat-file", "-p", f"{cid}:{HOOK}") == "EVIL\n"


def test_rehash_reads_each_object_once_per_call_and_honours_the_caps(dot, monkeypatch):
    """No forgery: the whole flow passes (the rest of the suite too); within one call an object is re-hashed once (`r.verified`);
    more than _MAX_OBJECTS objects or _MAX_OBJECT_BYTES bytes is an error, not a skipped check."""
    _, wt, base = dot
    _w(wt / "src/n.go")
    real, asked = sa._cat, []

    def spy(r, want, keep):
        asked.extend(want if not keep else ())
        return real(r, want, keep)

    monkeypatch.setattr(sa, "_cat", spy)
    st = run(_p.stage_task(str(wt), base))
    assert st["exit_code"] == 0 and asked and len(asked) == len(set(asked)), st
    assert _sha_of("blob", b"x\n") in asked and _git(wt, "rev-parse", f"{base}^{{tree}}").strip() in asked
    for cap, val in (("_MAX_OBJECTS", 3), ("_MAX_OBJECT_BYTES", 100)):
        with monkeypatch.context() as mp:
            mp.setattr(sa, cap, val)
            r = run(_p.stage_task(str(wt), base))
            assert r["exit_code"] != 0 and f"more than {val}" in r["error"] and "tree" not in r, r
