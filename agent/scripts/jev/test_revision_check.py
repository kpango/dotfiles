"""Regression tests for agent/scripts/jev/revision_check.py (T9/T10/T11's shared
I-13 revision gate), focused on the Checker-reported defect (revision 2 review):
a non-UTF-8 or permission-denied `dockers/laya.Dockerfile` previously propagated
an uncaught exception out of `load_verified_calibration()`, crashing every one of
guard_advisor.apply()/tier_advisor.advise()/evidence_reducer._reducer_rank_enabled()
and, transitively, decide.py itself (see test_decide_integration.py's own
end-to-end reproduction of that crash-then-fallback-to-allow chain)."""
import json
import os
import shutil
import sys
import tempfile
import unittest

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TEST_DIR)

import revision_check  # noqa: E402

TEST_REVISION = "a" * 40


def _write_revision_calibration(revision=TEST_REVISION):
    data = {"revision": revision, "capabilities": {"guard_deny": {"enabled": True, "threshold": 0.5}}}
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    return path


class TestNoLayaTorchImport(unittest.TestCase):
    def test_calibrate_import_does_not_pull_in_laya_or_torch(self):
        self.assertNotIn("laya", sys.modules)
        self.assertNotIn("torch", sys.modules)


class TestDockerfileReadFailuresDoNotCrash(unittest.TestCase):
    """Checker-reproduced defect: calibrate.check_dockerfile_revision() itself
    has no try/except around its own `open(...).read()` (it's a standalone
    script meant to fail loudly by hand) -- confirmed directly below that it
    really does raise for both cases before asserting revision_check survives
    them."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.calib_path = _write_revision_calibration()

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)
        os.unlink(self.calib_path)

    def test_calibrate_itself_really_does_raise_on_non_utf8(self):
        """Confirms the underlying defect exists in calibrate.py (not asserting
        against a hypothetical) before testing revision_check's own fix."""
        sys.path.insert(0, os.path.join(TEST_DIR, "calibration"))
        import calibrate

        path = os.path.join(self.tmpdir, "non_utf8.Dockerfile")
        with open(path, "wb") as f:
            f.write(b"ARG LAYA_HF_REVISION=" + b"a" * 40 + b"\n\xff\xfe not valid utf-8")
        with self.assertRaises(UnicodeDecodeError):
            calibrate.check_dockerfile_revision(path, TEST_REVISION)

    def test_calibrate_itself_really_does_raise_on_permission_denied(self):
        if os.geteuid() == 0:
            self.skipTest("running as root bypasses chmod 000 (no permission check to exercise)")
        path = os.path.join(self.tmpdir, "no_perm.Dockerfile")
        with open(path, "w", encoding="utf-8") as f:
            f.write("ARG LAYA_HF_REVISION=" + "a" * 40)
        os.chmod(path, 0o000)
        try:
            sys.path.insert(0, os.path.join(TEST_DIR, "calibration"))
            import calibrate

            with self.assertRaises(PermissionError):
                calibrate.check_dockerfile_revision(path, TEST_REVISION)
        finally:
            os.chmod(path, 0o644)

    def test_non_utf8_dockerfile_forces_disabled_not_a_crash(self):
        path = os.path.join(self.tmpdir, "non_utf8.Dockerfile")
        with open(path, "wb") as f:
            f.write(b"ARG LAYA_HF_REVISION=" + b"a" * 40 + b"\n\xff\xfe not valid utf-8")
        result = revision_check.load_verified_calibration(calibration_file=self.calib_path, dockerfile_path=path)
        self.assertIsNotNone(result)
        self.assertFalse(result["capabilities"]["guard_deny"]["enabled"])

    def test_permission_denied_dockerfile_forces_disabled_not_a_crash(self):
        if os.geteuid() == 0:
            self.skipTest("running as root bypasses chmod 000 (no permission check to exercise)")
        path = os.path.join(self.tmpdir, "no_perm.Dockerfile")
        with open(path, "w", encoding="utf-8") as f:
            f.write("ARG LAYA_HF_REVISION=" + "a" * 40)
        os.chmod(path, 0o000)
        try:
            result = revision_check.load_verified_calibration(calibration_file=self.calib_path, dockerfile_path=path)
            self.assertIsNotNone(result)
            self.assertFalse(result["capabilities"]["guard_deny"]["enabled"])
        finally:
            os.chmod(path, 0o644)

    def test_malformed_calibration_json_returns_none_not_a_crash(self):
        fd, bad_calib = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as f:
            f.write("not json{{{")
        try:
            result = revision_check.load_verified_calibration(calibration_file=bad_calib)
            self.assertIsNone(result)
        finally:
            os.unlink(bad_calib)


if __name__ == "__main__":
    unittest.main()
