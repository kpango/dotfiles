"""Regression tests for agent/scripts/jev/tier_advisor.py (T10, CONTEXT.md
"ai-env-deepresearch-overhaul" I-4/I-13). Fully offline, same MockLayaServer as
test_guard_advisor.py. Every "enabled" fixture carries a matching revision +
Dockerfile pair (test_support_revision_fixture) -- see test_guard_advisor.py's
own module docstring for why that is required."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TEST_DIR)

import tier_advisor  # noqa: E402
from test_support_mock_laya import MockLayaServer  # noqa: E402
from test_support_revision_fixture import (  # noqa: E402
    TEST_REVISION,
    write_dockerfile,
    _RevisionFixtureMixin,
)


def _write_tier_calibration(enabled, revision=TEST_REVISION):
    data = {"capabilities": {"tier_raise": {"enabled": enabled, "threshold": None}}}
    if revision is not None:
        data["revision"] = revision
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    return path


class TestNoOpWhenDisabled(_RevisionFixtureMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.server = MockLayaServer()
        self.calib_disabled = _write_tier_calibration(False)

    def tearDown(self):
        self.server.shutdown()
        os.unlink(self.calib_disabled)
        super().tearDown()

    def test_zero_requests_and_deterministic_tier_returned(self):
        result = tier_advisor.advise(
            "simple", "add a constant", calibration_file=self.calib_disabled,
            endpoint=self.server.url, dockerfile_path=self.dockerfile_path,
        )
        self.assertEqual(result["tier"], "simple")
        self.assertEqual(result["source"], "deterministic")
        self.assertFalse(result["raised"])
        self.assertEqual(len(self.server.requests), 0)

    def test_zero_requests_with_real_committed_calibration(self):
        result = tier_advisor.advise("trivial", "rename a variable", endpoint=self.server.url)
        self.assertEqual(result["tier"], "trivial")
        self.assertEqual(result["source"], "deterministic")
        self.assertEqual(len(self.server.requests), 0)


class TestRevisionGate(_RevisionFixtureMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.server = MockLayaServer()
        self.server.answer_fn = lambda qid, q, req: {"type": "choice", "choice": "complex", "confidence": 0.9}

    def tearDown(self):
        self.server.shutdown()
        super().tearDown()

    def test_missing_revision_field_forces_disabled(self):
        calib = _write_tier_calibration(True, revision=None)
        try:
            result = tier_advisor.advise(
                "simple", "some task", calibration_file=calib,
                endpoint=self.server.url, dockerfile_path=self.dockerfile_path,
            )
            self.assertEqual(result["source"], "deterministic")
            self.assertEqual(len(self.server.requests), 0)
        finally:
            os.unlink(calib)

    def test_mismatched_dockerfile_forces_disabled(self):
        other_dir = tempfile.mkdtemp()
        try:
            mismatched = write_dockerfile(other_dir, "c" * 40)
            calib = _write_tier_calibration(True)
            try:
                result = tier_advisor.advise(
                    "simple", "some task", calibration_file=calib,
                    endpoint=self.server.url, dockerfile_path=mismatched,
                )
                self.assertEqual(result["source"], "deterministic")
                self.assertEqual(len(self.server.requests), 0)
            finally:
                os.unlink(calib)
        finally:
            shutil.rmtree(other_dir, ignore_errors=True)

    def test_non_utf8_dockerfile_falls_back_to_deterministic_not_a_crash(self):
        """Checker-reported defect (revision 2 review), same root cause as
        guard_advisor's own test of the same name: a non-UTF-8 Dockerfile must
        degrade `advise()` to the deterministic tier, not raise."""
        path = os.path.join(self.dockerfile_dir, "non_utf8.Dockerfile")
        with open(path, "wb") as f:
            f.write(b"ARG LAYA_HF_REVISION=" + TEST_REVISION.encode() + b"\n\xff\xfe not valid utf-8")
        calib = _write_tier_calibration(True)
        try:
            result = tier_advisor.advise(
                "simple", "some task", calibration_file=calib,
                endpoint=self.server.url, dockerfile_path=path,
            )
            self.assertEqual(result["tier"], "simple")
            self.assertEqual(result["source"], "deterministic")
            self.assertEqual(len(self.server.requests), 0)
        finally:
            os.unlink(calib)

    def test_permission_denied_dockerfile_falls_back_to_deterministic_not_a_crash(self):
        if os.geteuid() == 0:
            self.skipTest("running as root bypasses chmod 000 (no permission check to exercise)")
        path = os.path.join(self.dockerfile_dir, "no_perm.Dockerfile")
        with open(path, "w", encoding="utf-8") as f:
            f.write("ARG LAYA_HF_REVISION=" + TEST_REVISION)
        os.chmod(path, 0o000)
        calib = _write_tier_calibration(True)
        try:
            result = tier_advisor.advise(
                "simple", "some task", calibration_file=calib,
                endpoint=self.server.url, dockerfile_path=path,
            )
            self.assertEqual(result["tier"], "simple")
            self.assertEqual(result["source"], "deterministic")
            self.assertEqual(len(self.server.requests), 0)
        finally:
            os.chmod(path, 0o644)
            os.unlink(calib)


class TestCLISurvivesAdviseCrash(unittest.TestCase):
    """Checker-reported defect (revision 2 review): tier_advisor.py's own
    documented contract is "ALWAYS exit 0" -- an uncaught exception inside
    advise() previously broke that (traceback on stderr, exit 1). Simulated
    here via a permission-denied Dockerfile passed straight through the real
    CLI subprocess (not just the importable advise() function), so this
    exercises main()'s own try/except too, not only advise()'s."""

    def test_cli_survives_permission_denied_dockerfile_exit_0_valid_json(self):
        if os.geteuid() == 0:
            self.skipTest("running as root bypasses chmod 000 (no permission check to exercise)")
        tmpdir = tempfile.mkdtemp()
        try:
            path = os.path.join(tmpdir, "no_perm.Dockerfile")
            with open(path, "w", encoding="utf-8") as f:
                f.write("ARG LAYA_HF_REVISION=" + TEST_REVISION)
            os.chmod(path, 0o000)
            calib = _write_tier_calibration(True)
            try:
                proc = subprocess.run(
                    [
                        sys.executable,
                        os.path.join(TEST_DIR, "tier_advisor.py"),
                        "--deterministic-tier", "simple",
                        "--description", "some task",
                        "--calibration-file", calib,
                        "--dockerfile-path", path,
                    ],
                    capture_output=True, text=True, timeout=15,
                )
                self.assertEqual(proc.returncode, 0)
                out = json.loads(proc.stdout.strip())
                self.assertEqual(out["tier"], "simple")
                self.assertEqual(out["source"], "deterministic")
            finally:
                os.chmod(path, 0o644)
                os.unlink(calib)
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)


class TestNeverLowers(_RevisionFixtureMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.server = MockLayaServer()
        self.calib_enabled = _write_tier_calibration(True)

    def tearDown(self):
        self.server.shutdown()
        os.unlink(self.calib_enabled)
        super().tearDown()

    def _advise(self, deterministic_tier, description):
        return tier_advisor.advise(
            deterministic_tier, description, calibration_file=self.calib_enabled,
            endpoint=self.server.url, dockerfile_path=self.dockerfile_path,
        )

    def test_laya_picks_lower_tier_deterministic_wins(self):
        self.server.answer_fn = lambda qid, q, req: {"type": "choice", "choice": "trivial", "confidence": 0.9}
        result = self._advise("complex", "some task")
        self.assertEqual(result["tier"], "complex")
        self.assertEqual(result["source"], "deterministic")
        self.assertFalse(result["raised"])
        self.assertEqual(result["laya_tier"], "trivial")

    def test_laya_picks_same_tier_deterministic_wins(self):
        self.server.answer_fn = lambda qid, q, req: {"type": "choice", "choice": "simple", "confidence": 0.9}
        result = self._advise("simple", "some task")
        self.assertEqual(result["tier"], "simple")
        self.assertEqual(result["source"], "deterministic")
        self.assertFalse(result["raised"])

    def test_laya_picks_higher_tier_laya_wins(self):
        self.server.answer_fn = lambda qid, q, req: {"type": "choice", "choice": "complex", "confidence": 0.8}
        result = self._advise("simple", "some task")
        self.assertEqual(result["tier"], "complex")
        self.assertEqual(result["source"], "laya")
        self.assertTrue(result["raised"])
        self.assertEqual(result["laya_confidence"], 0.8)


class TestFailToDeterministic(_RevisionFixtureMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.server = MockLayaServer()
        self.calib_enabled = _write_tier_calibration(True)

    def tearDown(self):
        self.server.shutdown()
        os.unlink(self.calib_enabled)
        super().tearDown()

    def test_http_error_falls_back(self):
        self.server.status = 500
        result = tier_advisor.advise(
            "standard", "some task", calibration_file=self.calib_enabled,
            endpoint=self.server.url, dockerfile_path=self.dockerfile_path,
        )
        self.assertEqual(result["tier"], "standard")
        self.assertEqual(result["source"], "deterministic")


class TestCLI(unittest.TestCase):
    def test_cli_exit_0_and_json_stdout(self):
        proc = subprocess.run(
            [
                sys.executable,
                os.path.join(TEST_DIR, "tier_advisor.py"),
                "--deterministic-tier", "trivial",
                "--description", "rename a constant",
            ],
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout.strip())
        self.assertEqual(out["tier"], "trivial")

    def test_cli_bad_tier_is_usage_error(self):
        proc = subprocess.run(
            [
                sys.executable,
                os.path.join(TEST_DIR, "tier_advisor.py"),
                "--deterministic-tier", "not-a-real-tier",
                "--description", "x",
            ],
            capture_output=True, text=True, timeout=15,
        )
        self.assertNotEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main()
