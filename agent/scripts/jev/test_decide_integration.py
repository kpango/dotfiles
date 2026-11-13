"""End-to-end tests of the *patched* agent/scripts/hooks/decide.py CLI (T9/I-14),
run as a real subprocess exactly the way agent/hooks/{claude,agy}/security-gate.sh
and agent/hooks/pi/security-gate.ts invoke it -- via stdin JSON in, one line of
stdout JSON out, exit code 0 always for a recognized family.

Lives under agent/scripts/jev/ rather than agent/scripts/hooks/ so that this new
test file is Tier A (agent/scripts/hooks/*.py is Tier B protected per
agent/write-scope-rules.json's suffix_patterns; test files under agent/scripts/jev/
are not -- only its production modules are, per CONTEXT.md I-15).

Isolation (Checker, revision 3 review): every test that needs a specific
calibration/Dockerfile *content* runs against a throwaway copy of decide.py's
whole security_shell dependency chain under its own tempdir -- see
`_build_isolated_source_tree()` below for why. The only tests that touch the
REAL, committed agent/scripts/jev/calibration/laya-calibration.json and
dockers/laya.Dockerfile are read-only (TestRealCommittedCalibrationIsANoOp,
TestProductionFilesNeverMutated) -- neither ever opens either path for
writing.
"""
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
AGENT_DIR = os.path.dirname(os.path.dirname(TEST_DIR))  # .../agent
HOOKS_DIR = os.path.join(AGENT_DIR, "scripts", "hooks")
DECIDE = os.path.join(HOOKS_DIR, "decide.py")
RULES_FILE = os.path.join(AGENT_DIR, "security-rules.json")
CALIB_PATH = os.path.join(TEST_DIR, "calibration", "laya-calibration.json")
DOCKERFILE_PATH = os.path.join(os.path.dirname(AGENT_DIR), "dockers", "laya.Dockerfile")

sys.path.insert(0, TEST_DIR)
from test_support_mock_laya import MockLayaServer  # noqa: E402
from test_support_revision_fixture import TEST_REVISION, write_dockerfile  # noqa: E402


def _sha256_of(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


# Captured at module-import time, i.e. before ANY test in this file (or any
# other file run in the same process) has had a chance to run -- the "before"
# half of TestProductionFilesNeverMutated's before/after comparison. Both
# paths are read here, never opened for writing, anywhere in this module.
_PROD_CALIB_SHA_AT_IMPORT = _sha256_of(CALIB_PATH)
_PROD_DOCKERFILE_SHA_AT_IMPORT = _sha256_of(DOCKERFILE_PATH) if os.path.exists(DOCKERFILE_PATH) else None


def _build_isolated_source_tree(dest_root):
    """Copies decide.py's whole security_shell dependency chain (decide.py,
    rule_engine.py, guard_advisor.py, revision_check.py, questions.py,
    jev_client.py, calibrate.py) into dest_root, preserving the relative
    directory layout guard_advisor/revision_check depend on for their own
    DEFAULT_CALIBRATION_FILE/DEFAULT_DOCKERFILE_PATH (both computed relative to
    revision_check.py's own __file__ -- decide.py's request JSON has no way to
    override either path). Returns a dict of the paths tests should write
    calibration/Dockerfile *content* to -- this function itself never copies
    the real laya-calibration.json/laya.Dockerfile content, only the source
    (.py) files, so the isolated tree starts with no calibration/Dockerfile at
    all until a test writes one.

    Why this exists (Checker-reported issue, revision 3 review): a previous
    version of these tests wrote calibration/dockerfile content directly at
    CALIB_PATH/DOCKERFILE_PATH above -- i.e. the REAL, production
    agent/scripts/jev/calibration/laya-calibration.json and
    dockers/laya.Dockerfile -- backing up and restoring the original content
    in tearDown(). Running these tests against a real checkout therefore
    mutated production guardrail state (e.g. temporarily enabling
    guard_relax) for the test's duration, visible to any OTHER concurrent
    session invoking decide.py against the same checkout; a SIGKILL or a
    setUp() exception before the restore ran (as genuinely happened once
    during this mission -- see the draft's §7.9 test-hygiene incident writeup)
    left it mutated indefinitely. Every test in this file that needs
    non-default calibration/Dockerfile content now runs against its own
    throwaway copy instead; the real files are never opened for writing by
    this file, at all, any more (TestProductionFilesNeverMutated below is the
    regression guard for that invariant, re-checked on every test run)."""
    hooks_src = HOOKS_DIR
    jev_src = os.path.join(AGENT_DIR, "scripts", "jev")
    hooks_dst = os.path.join(dest_root, "agent", "scripts", "hooks")
    jev_dst = os.path.join(dest_root, "agent", "scripts", "jev")
    calib_dst_dir = os.path.join(jev_dst, "calibration")
    dockers_dst_dir = os.path.join(dest_root, "dockers")
    os.makedirs(hooks_dst, exist_ok=True)
    os.makedirs(calib_dst_dir, exist_ok=True)
    os.makedirs(dockers_dst_dir, exist_ok=True)
    for name in ("decide.py", "rule_engine.py"):
        shutil.copy(os.path.join(hooks_src, name), os.path.join(hooks_dst, name))
    for name in ("guard_advisor.py", "revision_check.py", "questions.py", "jev_client.py"):
        shutil.copy(os.path.join(jev_src, name), os.path.join(jev_dst, name))
    shutil.copy(os.path.join(jev_src, "calibration", "calibrate.py"), os.path.join(calib_dst_dir, "calibrate.py"))
    return {
        "decide": os.path.join(hooks_dst, "decide.py"),
        "calibration_file": os.path.join(calib_dst_dir, "laya-calibration.json"),
        "dockers_dir": dockers_dst_dir,
        "dockerfile": os.path.join(dockers_dst_dir, "laya.Dockerfile"),
    }


def _run_decide(command, env=None, harness="claude", decide_path=None):
    req = {
        "family": "security_shell",
        "command": command,
        "cwd": ".",
        "rules_file": RULES_FILE,
        "resolve_command_target": False,
    }
    if harness is not None:
        req["harness"] = harness
    proc = subprocess.run(
        [sys.executable, decide_path or DECIDE],
        input=json.dumps(req),
        capture_output=True, text=True, timeout=15,
        env={**os.environ, **(env or {})},
    )
    return proc


class TestProductionFilesNeverMutated(unittest.TestCase):
    """Regression guard (Checker-reported issue, revision 3 review): no test in
    this module may ever write to the REAL agent/scripts/jev/calibration/
    laya-calibration.json or dockers/laya.Dockerfile. Compares against the
    sha256 captured at module-import time, i.e. before any test (in this file
    or any other file run in the same process) has executed."""

    def test_production_calibration_and_dockerfile_unchanged(self):
        self.assertEqual(
            _sha256_of(CALIB_PATH), _PROD_CALIB_SHA_AT_IMPORT,
            "a test in this module wrote to the REAL production "
            "laya-calibration.json -- every test needing non-default "
            "calibration content must use _build_isolated_source_tree() "
            "instead",
        )
        dockerfile_exists_now = os.path.exists(DOCKERFILE_PATH)
        self.assertEqual(
            dockerfile_exists_now, _PROD_DOCKERFILE_SHA_AT_IMPORT is not None,
            "dockers/laya.Dockerfile's existence changed during this test run",
        )
        if dockerfile_exists_now:
            self.assertEqual(
                _sha256_of(DOCKERFILE_PATH), _PROD_DOCKERFILE_SHA_AT_IMPORT,
                "a test in this module wrote to the REAL production "
                "dockers/laya.Dockerfile -- every test needing non-default "
                "Dockerfile content must use _build_isolated_source_tree() "
                "instead",
            )


class TestPeekConstantsMatchGuardAdvisor(unittest.TestCase):
    """decide.py keeps its own copy of `_GUARD_CAPABILITY_NAMES`/`_KNOWN_HARNESSES`
    (deliberately, so importing guard_advisor itself is not required just to read
    them -- see decide.py's own perf comment) -- pin that the two copies agree,
    so a future edit to one side cannot silently drift from the other. Reads
    the real decide.py/guard_advisor.py; writes nothing."""

    def test_constants_match(self):
        decide_spec = importlib.util.spec_from_file_location("decide_under_test", DECIDE)
        decide_mod = importlib.util.module_from_spec(decide_spec)
        decide_spec.loader.exec_module(decide_mod)

        jev_dir = os.path.join(AGENT_DIR, "scripts", "jev")
        sys.path.insert(0, jev_dir)
        import guard_advisor  # noqa: E402

        self.assertEqual(set(decide_mod._GUARD_CAPABILITY_NAMES), set(guard_advisor._GUARD_CAPABILITIES))
        self.assertEqual(set(decide_mod._KNOWN_HARNESSES), set(guard_advisor._KNOWN_HARNESSES))

    def test_calibration_file_path_matches(self):
        """decide.py's own comment on `_GUARD_CALIBRATION_FILE` claims this path must
        equal `guard_advisor.DEFAULT_CALIBRATION_FILE` -- unlike the capability-name/
        harness sets above, that specific claim was previously NOT checked by this
        class (T20 finding), so this test pins it explicitly. Compares realpath()
        of both sides rather than the raw strings, since decide.py builds its copy
        via `Path(...).resolve()` while guard_advisor's (via revision_check.py) uses
        `os.path.join` -- the two constructions are not guaranteed to produce
        byte-identical strings even when they name the same file."""
        decide_spec = importlib.util.spec_from_file_location("decide_under_test", DECIDE)
        decide_mod = importlib.util.module_from_spec(decide_spec)
        decide_spec.loader.exec_module(decide_mod)

        jev_dir = os.path.join(AGENT_DIR, "scripts", "jev")
        sys.path.insert(0, jev_dir)
        import guard_advisor  # noqa: E402

        self.assertEqual(
            os.path.realpath(decide_mod._GUARD_CALIBRATION_FILE),
            os.path.realpath(guard_advisor.DEFAULT_CALIBRATION_FILE),
        )


class TestRealCommittedCalibrationIsANoOp(unittest.TestCase):
    """The actual laya-calibration.json T17 committed has every guard_* capability
    disabled -- decide.py's behavior for security_shell must be unaffected, and
    must issue zero HTTP calls even if a (mis-)configured TYPESAFE_API_URL pointed
    at a live server, for every known harness. Reads the real, committed
    calibration file; never opens it for writing."""

    def setUp(self):
        self.server = MockLayaServer()

    def tearDown(self):
        self.server.shutdown()

    def test_allow_command_unaffected_zero_requests(self):
        for harness in ("claude", "agy", "pi"):
            with self.subTest(harness=harness):
                proc = _run_decide("ls -la", env={"TYPESAFE_API_URL": self.server.url}, harness=harness)
                self.assertEqual(proc.returncode, 0)
                out = json.loads(proc.stdout.strip())
                self.assertEqual(out["decision"], "allow")
                self.assertNotIn("laya", out)
        self.assertEqual(len(self.server.requests), 0)

    def test_block_command_unaffected_zero_requests(self):
        proc = _run_decide("rm -rf /", env={"TYPESAFE_API_URL": self.server.url})
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "block")
        self.assertEqual(out["matched_rule_id"], "rm_rf_root_home")
        self.assertNotIn("laya", out)
        self.assertEqual(len(self.server.requests), 0)


class TestHarnessGateThroughDecidePy(unittest.TestCase):
    """I-14: harness must be one of "claude"/"agy"/"pi", or the System-1 layer is
    a complete no-op -- exercised with a calibration that WOULD otherwise fire,
    to prove the gate (not just "nothing was enabled anyway"). Runs against an
    isolated copy (_build_isolated_source_tree()), never the real
    laya-calibration.json/laya.Dockerfile."""

    def setUp(self):
        self.server = MockLayaServer()
        self.server.answer_fn = lambda qid, q, req: {"type": "noul", "noul": 0.99}
        self.tmp_root = tempfile.mkdtemp()
        self.paths = _build_isolated_source_tree(self.tmp_root)
        with open(self.paths["calibration_file"], "w", encoding="utf-8") as f:
            json.dump({"revision": TEST_REVISION, "capabilities": {"guard_deny": {"enabled": True, "threshold": 0.5}}}, f)
        write_dockerfile(self.paths["dockers_dir"], TEST_REVISION)

    def tearDown(self):
        self.server.shutdown()
        shutil.rmtree(self.tmp_root, ignore_errors=True)

    def test_missing_harness_is_a_no_op(self):
        proc = _run_decide("cat ~/.aws/credentials", env={"TYPESAFE_API_URL": self.server.url}, harness=None, decide_path=self.paths["decide"])
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "allow")
        self.assertNotIn("laya", out)
        self.assertEqual(len(self.server.requests), 0)

    def test_unknown_harness_is_a_no_op(self):
        proc = _run_decide("cat ~/.aws/credentials", env={"TYPESAFE_API_URL": self.server.url}, harness="codex", decide_path=self.paths["decide"])
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "allow")
        self.assertNotIn("laya", out)
        self.assertEqual(len(self.server.requests), 0)

    def test_known_harness_triggers_system1(self):
        proc = _run_decide("cat ~/.aws/credentials", env={"TYPESAFE_API_URL": self.server.url}, harness="claude", decide_path=self.paths["decide"])
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "block")
        self.assertEqual(out["laya"]["applied_capability"], "guard_deny")


class TestGuardDenyEscalatesThroughDecidePy(unittest.TestCase):
    """Runs against an isolated copy (_build_isolated_source_tree()) so each
    test can freely rewrite calibration/Dockerfile *content* without ever
    touching the real, committed files -- the isolated tempdir is destroyed in
    tearDown(), nothing to restore."""

    def setUp(self):
        self.server = MockLayaServer()
        self.tmp_root = tempfile.mkdtemp()
        self.paths = _build_isolated_source_tree(self.tmp_root)
        write_dockerfile(self.paths["dockers_dir"], TEST_REVISION)

    def tearDown(self):
        self.server.shutdown()
        shutil.rmtree(self.tmp_root, ignore_errors=True)

    def _set_calibration(self, capabilities):
        with open(self.paths["calibration_file"], "w", encoding="utf-8") as f:
            json.dump({"revision": TEST_REVISION, "capabilities": capabilities}, f)

    def test_deny_enabled_escalates_allow_to_block(self):
        # A command that matches none of security-rules.json's deterministic
        # rules (deterministic decision is "allow"), so the escalation below is
        # solely guard_deny's doing.
        self._set_calibration({"guard_deny": {"enabled": True, "threshold": 0.5}})
        self.server.answer_fn = lambda qid, q, req: {"type": "noul", "noul": 0.99}
        proc = _run_decide("cat ~/.aws/credentials", env={"TYPESAFE_API_URL": self.server.url}, decide_path=self.paths["decide"])
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "block")
        self.assertEqual(out["laya"]["applied_capability"], "guard_deny")
        self.assertEqual(len(self.server.requests), 1)

    def test_deterministic_block_is_never_relaxed_even_with_relax_enabled(self):
        """I-2 hard floor: even with guard_relax enabled and Laya scoring the
        command as very safe, a deterministic block must remain block."""
        self._set_calibration({"guard_relax": {"enabled": True, "threshold": 0.9}})
        self.server.answer_fn = lambda qid, q, req: {"type": "noul", "noul": 0.0}
        proc = _run_decide("rm -rf /", env={"TYPESAFE_API_URL": self.server.url}, decide_path=self.paths["decide"])
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "block")
        self.assertNotIn("laya", out)
        self.assertEqual(len(self.server.requests), 0)

    def test_laya_unreachable_falls_back_to_deterministic(self):
        self._set_calibration({"guard_deny": {"enabled": True, "threshold": 0.5}})
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.bind(("127.0.0.1", 0))
        dead_port = s.getsockname()[1]
        s.close()
        dead_url = "http://127.0.0.1:%d/v1/systemone" % dead_port
        proc = _run_decide("ls -la", env={"TYPESAFE_API_URL": dead_url}, decide_path=self.paths["decide"])
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "allow")

    def test_agy_harness_never_relaxes_even_when_calibration_enables_it(self):
        """I-14 exercised through the real decide.py boundary, not just
        guard_advisor.apply() directly. "git clean -f" deterministically matches
        the ask-tier git_clean_force_only rule (confirmed against
        agent/security-rules.json), so the deterministic starting decision is
        "ask" -- exactly guard_relax's own precondition."""
        self._set_calibration({"guard_relax": {"enabled": True, "threshold": 0.9}})
        self.server.answer_fn = lambda qid, q, req: {"type": "noul", "noul": 0.01}  # very safe

        proc_agy = _run_decide("git clean -f", env={"TYPESAFE_API_URL": self.server.url}, harness="agy", decide_path=self.paths["decide"])
        out_agy = json.loads(proc_agy.stdout.strip())
        self.assertEqual(out_agy["decision"], "ask")  # NOT relaxed for agy
        self.assertNotIn("laya", out_agy)  # guard_relax was the only enabled capability -> no-op for agy

        # Same command, same probability, harness="claude" -- confirms the
        # suppression above is agy-specific, not a global regression (relax
        # actually fires and produces "allow" here).
        proc_claude = _run_decide("git clean -f", env={"TYPESAFE_API_URL": self.server.url}, harness="claude", decide_path=self.paths["decide"])
        out_claude = json.loads(proc_claude.stdout.strip())
        self.assertEqual(out_claude["decision"], "allow")
        self.assertEqual(out_claude["laya"]["applied_capability"], "guard_relax")


class TestDecideSurvivesRevisionCheckCrash(unittest.TestCase):
    """Checker-reported defect (revision 2 review), reproduced and fixed
    end-to-end through the REAL decide.py subprocess boundary: only the
    `import guard_advisor` statement was wrapped in try/except; the
    `guard_advisor.apply(...)` CALL itself was not, and
    `revision_check.load_verified_calibration()` -> `calibrate.
    check_dockerfile_revision()` had a plain, unprotected `open(...).read()`.
    A non-UTF-8 or permission-denied `dockers/laya.Dockerfile` therefore
    propagated an uncaught exception all the way out of decide.py's `main()`,
    which exited non-zero with empty stdout -- and every one of the three
    shims' own "decide.py itself is unreachable" fallback then returned a
    blanket ALLOW (claude's `|| exit 0`, agy's `except Exception: return
    {"decision": "allow"}`, pi's `{decision: "allow"}` fallback), silently
    downgrading a deterministic "ask" to "allow". Both `guard_advisor.apply()`
    and `revision_check.load_verified_calibration()` now catch this
    internally, AND decide.py's own call site wraps it too (defense in
    depth) -- this test exercises the real decide.py subprocess, not just
    those functions directly, to confirm the whole chain actually holds.

    Runs against an isolated copy (_build_isolated_source_tree()) -- the
    chmod-000/non-UTF-8 Dockerfile fixture this test needs is exactly the
    kind of throwaway, deliberately-broken state that must never land on a
    real, shared file."""

    def setUp(self):
        self.server = MockLayaServer()
        self.tmp_root = tempfile.mkdtemp()
        self.paths = _build_isolated_source_tree(self.tmp_root)

    def tearDown(self):
        self.server.shutdown()
        # chmod 000 fixtures must be restored to a removable mode before
        # shutil.rmtree can delete them; ignore_errors covers anything else.
        dockerfile = self.paths["dockerfile"]
        if os.path.exists(dockerfile):
            os.chmod(dockerfile, 0o644)
        shutil.rmtree(self.tmp_root, ignore_errors=True)

    def _set_calibration_with_guard_deny(self):
        with open(self.paths["calibration_file"], "w", encoding="utf-8") as f:
            json.dump({"revision": TEST_REVISION, "capabilities": {"guard_deny": {"enabled": True, "threshold": 0.5}}}, f)

    def test_non_utf8_dockerfile_preserves_deterministic_ask_exit_0(self):
        self._set_calibration_with_guard_deny()
        self.server.answer_fn = lambda qid, q, req: {"type": "noul", "noul": 0.99}
        with open(self.paths["dockerfile"], "wb") as f:
            f.write(b"ARG LAYA_HF_REVISION=" + TEST_REVISION.encode() + b"\n\xff\xfe not valid utf-8")

        # "git clean -f" deterministically matches the ask-tier
        # git_clean_force_only rule (same fixture command used elsewhere in
        # this file) -- the deterministic decision is "ask", which the crash
        # bug would have silently downgraded to "allow".
        proc = _run_decide("git clean -f", env={"TYPESAFE_API_URL": self.server.url}, harness="claude", decide_path=self.paths["decide"])
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip().count("\n"), 0)  # exactly one line
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "ask")
        self.assertNotIn("laya", out)

    def test_permission_denied_dockerfile_preserves_deterministic_ask_exit_0(self):
        if os.geteuid() == 0:
            self.skipTest("running as root bypasses chmod 000 (no permission check to exercise)")
        self._set_calibration_with_guard_deny()
        self.server.answer_fn = lambda qid, q, req: {"type": "noul", "noul": 0.99}
        with open(self.paths["dockerfile"], "w", encoding="utf-8") as f:
            f.write("ARG LAYA_HF_REVISION=" + TEST_REVISION)
        os.chmod(self.paths["dockerfile"], 0o000)
        proc = _run_decide("git clean -f", env={"TYPESAFE_API_URL": self.server.url}, harness="claude", decide_path=self.paths["decide"])
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["decision"], "ask")
        self.assertNotIn("laya", out)


if __name__ == "__main__":
    unittest.main()
