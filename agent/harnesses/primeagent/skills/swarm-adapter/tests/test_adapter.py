"""Hermetic tests for the swarm-adapter thin wrapper (stub script roots + temp git repos)."""
import asyncio
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

import swarm_adapter as sa

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
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(Path(tmp_path_factory.getbasetemp()).resolve()))
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    monkeypatch.setenv("GIT_AUTHOR_NAME", "t")
    monkeypatch.setenv("GIT_AUTHOR_EMAIL", "t@t")
    monkeypatch.setenv("GIT_COMMITTER_NAME", "t")
    monkeypatch.setenv("GIT_COMMITTER_EMAIL", "t@t")


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
