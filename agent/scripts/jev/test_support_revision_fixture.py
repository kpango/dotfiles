"""Shared test fixtures for the I-13 revision gate (revision_check.py), used by
test_guard_advisor.py / test_tier_advisor.py / test_evidence_reducer.py /
test_decide_integration.py. Every calibration fixture those files construct must
carry a "revision" field, and callers must pass a `dockerfile_path` whose pinned
`LAYA_HF_REVISION` matches it, or `revision_check.load_verified_calibration()`
forces every capability's "enabled" back to False regardless of what the fixture
itself declares -- this module centralizes that boilerplate (Ponytail step 2)."""
import os
import shutil
import tempfile

TEST_REVISION = "a" * 40
MISMATCHED_REVISION = "b" * 40


def write_dockerfile(directory: str, revision: str) -> str:
    """Write a minimal Dockerfile fixture declaring `ARG LAYA_HF_REVISION=<revision>`
    and return its path. `revision_check.check_dockerfile_revision()` (via
    `calibrate.read_dockerfile_pinned_revision()`) only ever regexes for that one
    line, so nothing else in the file matters for these tests."""
    path = os.path.join(directory, "laya.Dockerfile")
    with open(path, "w", encoding="utf-8") as f:
        f.write("ARG LAYA_HF_REVISION=%s\n" % revision)
    return path


def matching_dockerfile(tmp_path_factory=None) -> str:
    """Convenience: a fresh temp dir + a Dockerfile pinned to TEST_REVISION."""
    d = tempfile.mkdtemp()
    return write_dockerfile(d, TEST_REVISION)


class _RevisionFixtureMixin:
    """setUp/tearDown for a temp dir holding a matching-revision Dockerfile
    fixture, shared by every TestCase (across test_guard_advisor.py /
    test_tier_advisor.py / test_evidence_reducer.py) that needs one. Uses
    `self.dockerfile_dir` (not `self.tmpdir`) for the temp dir so it never
    collides with a subclass's own, differently-purposed `self.tmpdir`
    (e.g. evidence_reducer's reduce_text `save_dir`)."""

    def setUp(self):
        self.dockerfile_dir = tempfile.mkdtemp()
        self.dockerfile_path = write_dockerfile(self.dockerfile_dir, TEST_REVISION)

    def tearDown(self):
        shutil.rmtree(self.dockerfile_dir, ignore_errors=True)
