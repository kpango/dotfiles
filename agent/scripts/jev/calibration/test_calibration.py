#!/usr/bin/env python3
"""Regression tests for agent/scripts/jev/calibration/laya-calibration.json and its
three source datasets (guard.jsonl / tier.jsonl / loglines.jsonl).

Stdlib-only, no `laya`/`torch` import -- unlike calibrate.py (which needs both to
actually run inference), these tests only check the *shape* and *internal
consistency* of already-produced data/output, so they run in the repo's ordinary
(laya-free) test environment via agent/scripts/test-jev-calibration.sh.

Six checks, matching the T17 task spec:
  (a) laya-calibration.json schema validation
  (b) recorded dataset_sha256 matches the current *.jsonl files (so editing data
      without recalibrating is caught mechanically)
  (c) recorded revision == the pinned sha; cross-checked against
      dockers/laya.Dockerfile's `ARG LAYA_HF_REVISION` (or, as a backward-compatible
      fallback during the T16/T17 migration, the legacy `LAYA_HF_EXPECTED_SHA`) when
      that file exists -- plus a standalone check (TestDockerfileRevisionCheckLogic)
      that this matching/mismatch logic itself is correct, using synthetic
      Dockerfile fragments written to temp files, independent of whether the real
      dockers/laya.Dockerfile exists in this worktree yet
  (d) every capability with enabled=true actually satisfies its stated held-out
      condition, recomputed independently from the recorded metrics (so hand-editing
      "enabled" to true without the metrics backing it up is caught mechanically)
  (e) dataset sizes and per-class minimums
  (f) drift detection (T17 attempt 4): the deterministic side of reducer_rank's
      recorded metrics still matches what questions.is_deterministic_critical()
      computes right now against loglines.jsonl's held-out half, so a regex edit
      that changes no dataset file (and so can't be caught by check (b)'s sha
      comparison) can't silently invalidate laya-calibration.json unnoticed
"""
import hashlib
import json
import os
import re
import sys
import tempfile
import unittest

CALIB_DIR = os.path.dirname(os.path.abspath(__file__))
JEV_DIR = os.path.dirname(CALIB_DIR)
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(JEV_DIR)))  # <root>/agent/scripts/jev -> <root>

# calibrate.py has no top-level laya/torch import (both are imported lazily, inside
# functions, only when actually running inference) -- so importing it here to reuse
# its Dockerfile-revision-parsing logic (rather than duplicating it) is safe from a
# laya-free test environment, and keeps this test's notion of "matches" identical to
# what calibrate.py itself checks at calibration time.
sys.path.insert(0, CALIB_DIR)
import calibrate as C  # noqa: E402

GUARD_PATH = os.path.join(CALIB_DIR, "guard.jsonl")
TIER_PATH = os.path.join(CALIB_DIR, "tier.jsonl")
LOGLINES_PATH = os.path.join(CALIB_DIR, "loglines.jsonl")
CALIBRATION_JSON_PATH = os.path.join(CALIB_DIR, "laya-calibration.json")
LAYA_DOCKERFILE_PATH = os.path.join(ROOT_DIR, "dockers", "laya.Dockerfile")

EXPECTED_REVISION = "bf2e02ac0a5f86d70c84adedd87c1c1dccdde0bc"

EXPECTED_CAPABILITIES = (
    "guard_strengthen",
    "guard_deny",
    "guard_relax",
    "tier_raise",
    "reducer_rank",
)

# Minimums from the T17 task spec.
MIN_GUARD_DANGEROUS = 100
MIN_GUARD_SAFE = 100
MIN_TIER_TOTAL = 80
MIN_TIER_PER_CLASS = 15  # "not too skewed" -- each of the 4 tiers must be meaningfully represented
MIN_LOGLINES_TOTAL = 150
MIN_LOGLINES_PER_CLASS = 30  # each of noise/context/critical must be meaningfully represented

TIER_LEVELS = ("trivial", "simple", "standard", "complex")
LOGLINE_LABELS = ("noise", "context", "critical")


def _load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


class CalibrationJsonExistsMixin:
    @classmethod
    def setUpClass(cls):
        if not os.path.exists(CALIBRATION_JSON_PATH):
            raise unittest.SkipTest(
                "%s does not exist yet -- run calibrate.py first "
                "(needs a laya/torch environment; see the file's own docstring)"
                % CALIBRATION_JSON_PATH
            )
        with open(CALIBRATION_JSON_PATH, encoding="utf-8") as f:
            cls.calibration = json.load(f)


class TestSchema(CalibrationJsonExistsMixin, unittest.TestCase):
    """(a) laya-calibration.json schema validation."""

    def test_top_level_keys(self):
        required = {
            "model_repo",
            "revision",
            "laya_version",
            "dataset_sha256",
            "created_at",
            "split_seed",
            "capabilities",
        }
        missing = required - set(self.calibration)
        self.assertFalse(missing, "missing top-level keys: %s" % missing)

    def test_top_level_types(self):
        self.assertIsInstance(self.calibration["model_repo"], str)
        self.assertIsInstance(self.calibration["revision"], str)
        self.assertIsInstance(self.calibration["laya_version"], str)
        self.assertIsInstance(self.calibration["dataset_sha256"], dict)
        self.assertIsInstance(self.calibration["created_at"], str)
        self.assertIsInstance(self.calibration["split_seed"], int)
        self.assertIsInstance(self.calibration["capabilities"], dict)

    def test_dataset_sha256_shape(self):
        sha_map = self.calibration["dataset_sha256"]
        for key in ("guard", "tier", "loglines"):
            self.assertIn(key, sha_map)
            value = sha_map[key]
            self.assertIsInstance(value, str)
            self.assertRegex(value, r"^[0-9a-f]{64}$", "%s sha256 is not a 64-hex digest" % key)

    def test_capabilities_present_and_shaped(self):
        caps = self.calibration["capabilities"]
        missing = set(EXPECTED_CAPABILITIES) - set(caps)
        self.assertFalse(missing, "missing capabilities: %s" % missing)
        for name, entry in caps.items():
            self.assertIsInstance(entry, dict, "%s is not a dict" % name)
            self.assertIn("enabled", entry, "%s missing 'enabled'" % name)
            self.assertIsInstance(entry["enabled"], bool, "%s.enabled is not a bool" % name)
            self.assertIn("metrics", entry, "%s missing 'metrics'" % name)
            self.assertIsInstance(entry["metrics"], dict, "%s.metrics is not a dict" % name)

    def test_guard_capabilities_have_threshold(self):
        caps = self.calibration["capabilities"]
        for name in ("guard_strengthen", "guard_deny", "guard_relax"):
            self.assertIn("threshold", caps[name], "%s missing 'threshold'" % name)
            self.assertIsInstance(caps[name]["threshold"], (int, float))


class TestDatasetShaMatchesCurrentFiles(CalibrationJsonExistsMixin, unittest.TestCase):
    """(b) recorded dataset_sha256 must match the *current* jsonl files -- a data
    edit without recalibration must be mechanically detectable."""

    def test_guard_sha_matches(self):
        self.assertEqual(
            self.calibration["dataset_sha256"]["guard"],
            _sha256_file(GUARD_PATH),
            "guard.jsonl has changed since laya-calibration.json was produced -- recalibrate",
        )

    def test_tier_sha_matches(self):
        self.assertEqual(
            self.calibration["dataset_sha256"]["tier"],
            _sha256_file(TIER_PATH),
            "tier.jsonl has changed since laya-calibration.json was produced -- recalibrate",
        )

    def test_loglines_sha_matches(self):
        self.assertEqual(
            self.calibration["dataset_sha256"]["loglines"],
            _sha256_file(LOGLINES_PATH),
            "loglines.jsonl has changed since laya-calibration.json was produced -- recalibrate",
        )


class TestRevisionPinned(CalibrationJsonExistsMixin, unittest.TestCase):
    """(c) revision must be the pinned sha; cross-checked against
    dockers/laya.Dockerfile's `ARG LAYA_HF_REVISION` (current name, T16) -- or, as a
    backward-compatible fallback during the T16/T17 migration window, the legacy
    `LAYA_HF_EXPECTED_SHA` -- when that file exists in this worktree (it is added by
    a separate task, so its absence here is expected and only skips the
    cross-check, not the pin check itself). Uses the exact same
    `calibrate.check_dockerfile_revision()` logic calibrate.py itself runs before
    calibrating, so this test can never drift from what calibration actually checks."""

    def test_revision_is_pinned_sha(self):
        self.assertEqual(self.calibration["revision"], EXPECTED_REVISION)

    def test_revision_matches_dockerfile_when_present(self):
        status, message = C.check_dockerfile_revision(LAYA_DOCKERFILE_PATH, EXPECTED_REVISION)
        if status == "skip":
            raise unittest.SkipTest(message)
        self.assertEqual(status, "ok", message)


class TestDockerfileRevisionCheckLogic(unittest.TestCase):
    """Standalone verification of calibrate.py's Dockerfile-revision matching/
    mismatch logic itself (`read_dockerfile_pinned_revision` /
    `check_dockerfile_revision`), using synthetic Dockerfile fragments written to
    real temp files -- independent of whether the real dockers/laya.Dockerfile
    exists in this worktree (T16 is a separate, possibly not-yet-landed task).
    This is what proves the logic gives PASS on a match and FAIL on a mismatch,
    rather than only ever having been exercised against a real Dockerfile."""

    def test_matching_current_var_name_passes(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "laya.Dockerfile")
            with open(path, "w", encoding="utf-8") as f:
                f.write("FROM kpango/tools:nightly\nARG LAYA_HF_REVISION=%s\nRUN true\n" % EXPECTED_REVISION)
            status, message = C.check_dockerfile_revision(path, EXPECTED_REVISION)
        self.assertEqual(status, "ok", message)

    def test_mismatched_current_var_name_fails(self):
        wrong_sha = "f" * 40
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "laya.Dockerfile")
            with open(path, "w", encoding="utf-8") as f:
                f.write("FROM kpango/tools:nightly\nARG LAYA_HF_REVISION=%s\nRUN true\n" % wrong_sha)
            status, message = C.check_dockerfile_revision(path, EXPECTED_REVISION)
        self.assertEqual(status, "fatal", message)

    def test_matching_legacy_var_name_passes_via_backward_compat(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "laya.Dockerfile")
            with open(path, "w", encoding="utf-8") as f:
                f.write("ARG LAYA_HF_EXPECTED_SHA=%s\n" % EXPECTED_REVISION)
            status, message = C.check_dockerfile_revision(path, EXPECTED_REVISION)
        self.assertEqual(status, "ok", message)

    def test_mismatched_legacy_var_name_fails(self):
        wrong_sha = "0" * 40
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "laya.Dockerfile")
            with open(path, "w", encoding="utf-8") as f:
                f.write("ARG LAYA_HF_EXPECTED_SHA=%s\n" % wrong_sha)
            status, message = C.check_dockerfile_revision(path, EXPECTED_REVISION)
        self.assertEqual(status, "fatal", message)

    def test_current_var_name_preferred_when_both_present(self):
        contents = "ARG LAYA_HF_EXPECTED_SHA=%s\nARG LAYA_HF_REVISION=%s\n" % ("2" * 40, EXPECTED_REVISION)
        var_name, sha = C.read_dockerfile_pinned_revision(contents)
        self.assertEqual(var_name, "LAYA_HF_REVISION")
        self.assertEqual(sha, EXPECTED_REVISION)

    def test_missing_dockerfile_skips_rather_than_fails(self):
        status, message = C.check_dockerfile_revision(
            "/nonexistent/path/does/not/exist/laya.Dockerfile", EXPECTED_REVISION
        )
        self.assertEqual(status, "skip", message)

    def test_dockerfile_with_neither_var_skips_rather_than_fails(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "laya.Dockerfile")
            with open(path, "w", encoding="utf-8") as f:
                f.write("FROM ubuntu:24.04\nRUN apt-get update\n")
            status, message = C.check_dockerfile_revision(path, EXPECTED_REVISION)
        self.assertEqual(status, "skip", message)


class TestModelDirRevisionCheckLogic(unittest.TestCase):
    """Standalone verification of calibrate.py's --model-dir provenance-checking
    logic (`resolve_model_dir_revision` / `check_model_dir_revision`), using real
    temp directories laid out exactly like huggingface_hub's own on-disk cache and
    local_dir formats (verified against the installed huggingface_hub's source, see
    those functions' docstrings) -- added after an independent Checker (T17 attempt
    3) found that passing --model-dir skipped snapshot_download (and therefore any
    revision check) entirely, so a stale/wrong-commit --model-dir was silently
    recorded as the pinned revision.
    """

    SHA = EXPECTED_REVISION
    OTHER_SHA = "1" * 40

    def test_snapshot_cache_dir_name_matching_passes(self):
        with tempfile.TemporaryDirectory() as d:
            snapshot_dir = os.path.join(d, "models--convaiinnovations--laya", "snapshots", self.SHA)
            os.makedirs(snapshot_dir)
            status, message = C.check_model_dir_revision(snapshot_dir, self.SHA)
        self.assertEqual(status, "ok", message)

    def test_snapshot_cache_dir_name_mismatching_fails(self):
        with tempfile.TemporaryDirectory() as d:
            snapshot_dir = os.path.join(d, "models--convaiinnovations--laya", "snapshots", self.OTHER_SHA)
            os.makedirs(snapshot_dir)
            status, message = C.check_model_dir_revision(snapshot_dir, self.SHA)
        self.assertEqual(status, "fatal", message)

    def test_local_dir_metadata_matching_passes(self):
        with tempfile.TemporaryDirectory() as d:
            meta_dir = os.path.join(d, ".cache", "huggingface", "download")
            os.makedirs(meta_dir)
            with open(os.path.join(meta_dir, "model.safetensors.metadata"), "w", encoding="utf-8") as f:
                f.write("%s\nsome-etag\n1712656091.123\n" % self.SHA)
            status, message = C.check_model_dir_revision(d, self.SHA)
        self.assertEqual(status, "ok", message)

    def test_local_dir_metadata_mismatching_fails(self):
        with tempfile.TemporaryDirectory() as d:
            meta_dir = os.path.join(d, ".cache", "huggingface", "download")
            os.makedirs(meta_dir)
            with open(os.path.join(meta_dir, "model.safetensors.metadata"), "w", encoding="utf-8") as f:
                f.write("%s\nsome-etag\n1712656091.123\n" % self.OTHER_SHA)
            status, message = C.check_model_dir_revision(d, self.SHA)
        self.assertEqual(status, "fatal", message)

    def test_local_dir_metadata_disagreeing_across_files_fails(self):
        with tempfile.TemporaryDirectory() as d:
            meta_dir = os.path.join(d, ".cache", "huggingface", "download")
            os.makedirs(meta_dir)
            with open(os.path.join(meta_dir, "a.metadata"), "w", encoding="utf-8") as f:
                f.write("%s\netag-a\n1712656091.123\n" % self.SHA)
            with open(os.path.join(meta_dir, "b.metadata"), "w", encoding="utf-8") as f:
                f.write("%s\netag-b\n1712656091.456\n" % self.OTHER_SHA)
            status, message = C.check_model_dir_revision(d, self.SHA)
        self.assertEqual(status, "fatal", message)

    def test_unverifiable_directory_fails_rather_than_silently_passing(self):
        with tempfile.TemporaryDirectory() as d:
            # A plain directory with model files but neither a snapshots/<sha> name
            # nor local_dir download metadata -- e.g. a hand-copied directory.
            with open(os.path.join(d, "model.safetensors"), "w", encoding="utf-8") as f:
                f.write("not a real checkpoint")
            status, message = C.check_model_dir_revision(d, self.SHA)
        self.assertEqual(status, "fatal", message)


class TestDeterministicCriticalPattern(unittest.TestCase):
    """Standalone positive/negative table for
    agent/scripts/jev/questions.py::is_deterministic_critical() /
    DETERMINISTIC_CRITICAL_PATTERN -- the Reducer's fail-to-deterministic fallback
    and reducer_rank's baseline. Added after an independent Checker (T17 attempt 2)
    reproduced the plain \\b-bounded keyword list this replaced as missing every
    CamelCase exception name (TypeError, KeyError, ModuleNotFoundError, RuntimeError,
    java.lang.NullPointerException) and "undefined_var is not defined" (the
    underscore blocks a plain `\\bundefined\\b`, since `\\b` treats `_` as a word
    character) -- and separately mis-flagging a passing summary line that merely
    *mentions* a zero failure count ("... 0 failed; ...") as critical. Extended
    again after a second independent Checker (T17 attempt 3) reproduced (a) plural
    failure summaries ("2 errors generated.", "Found 3 errors in 2 files", "10
    examples, 3 failures", "Tests run: 5, Failures: 2") being missed because the
    prior pattern's trailing `\\b` only fired on singular/verb forms, and (b) the
    CamelCase `...Error`/`...Exception` alternative false-positiving on an
    all-lowercase package name ("Downloading typeerror-polyfill") because the whole
    pattern's `(?i)` made that alternative's "Error"/"Exception" literal match
    lowercase text too.

    T17 attempts 4-5: attempt 3's plural fix was chased with a `_ZERO_COUNT_PATTERN`
    mask (to avoid "0 failed"/"no errors" reading as a failure) and, after attempt 4
    found that mask still missed a label-first order ("Failures: 0"), a second
    alternative and a path/filename lookaround guard on "errors" (to avoid
    "pkg/errors"/"errors.rs"). A third independent Checker (T17 attempt 5) reproduced
    real failure lines these exclusions masked as if they were mere absence-of-
    failure phrases -- "error: 0 is not a valid value for --jobs", "Check failed: 0
    == ret (0 vs. -1)", "foo_test.go:12: expected no error, got EOF" -- proving the
    exclusion-chasing itself was the recurring root cause (this pattern is a
    recall-first safety floor for the Reducer's fail-to-deterministic fallback: a
    missed real failure is a correctness bug, an extra kept noise/context line only
    costs a little compression). `_ZERO_COUNT_PATTERN` and the "errors" path/filename
    guard were both removed outright (not patched again).

    T17 attempt 6 (human-approved final correction): attempt 5's own claim that
    "every exclusion that could hide a real failure line was removed" was itself
    wrong -- `\b` and the `-` lookbehind kept for the `--no-fail-fast` case are
    exclusions of exactly that kind, and a fourth independent Checker reproduced
    real misses from both ("FATAL_ERROR: out of memory", "...'std::runtime_error'"
    missed by `\b`'s underscore handling; "build-failed", "health-check-failed:
    ..." missed by the `-` lookbehind). The pattern is now a plain, case-insensitive
    **substring** match with no word-boundary, lookaround, or exclusion logic
    whatsoever -- see questions.py's module-level design notes for the full
    rationale. This also makes the attempt-3 pluralization alternatives and the
    attempt-3 CamelCase case-sensitivity branch redundant (a plain substring
    "error" already matches "errors", "TypeError", and "ERROR" alike), so both are
    removed too. The false positives this reopens ("0 errors", "Failures: 0", "ℹ
    fail 0", a bare "panic.go" stack frame, "pkg/errors"/"errors.rs" paths,
    "error_handling.go", "--no-fail-fast", "Downloading typeerror-polyfill") are
    now pinned down as *accepted*, in ACCEPTED_FALSE_POSITIVES below, rather than
    asserted false. `TestDeterministicPatternHasNoExclusions` (below) mechanically
    guards against a future change silently reintroducing `\b`/lookaround.

    `calibrate.py` imports `questions` as `Q` (`C.Q` here) with no laya/torch
    dependency at import time, so reusing it is safe from this laya-free suite.
    """

    # (line, expect_critical) -- see questions.py's DETERMINISTIC_CRITICAL_PATTERN
    # design-notes comment for why each of these is expected to behave as it does.
    # These are all *genuine* failure/error lines -- a real regression that makes
    # any of these False again would hide a real failure from the Reducer.
    POSITIVE_CASES = (
        ("TypeError: unsupported operand type(s) for +: 'int' and 'str'", "CamelCase ...Error, Python"),
        ("KeyError", "CamelCase ...Error, bare"),
        ("ModuleNotFoundError: No module named 'requests'", "CamelCase ...Error, Python"),
        ("RuntimeError: boom", "CamelCase ...Error, generic"),
        ("java.lang.NullPointerException", "CamelCase ...Exception, Java, dotted-path prefix"),
        ("undefined_var is not defined", "undefined + underscore-continued identifier"),
        ("undefined: strings.CutPrefix", "undefined + colon, Go build error"),
        ("panic: runtime error: index out of range [3] with length 3", "Go panic:"),
        ("--- FAIL: TestParseConfig (0.01s)", "Go test --- FAIL summary"),
        ("error[E0433]: failed to resolve: use of undeclared crate or module", "Rust error[E....]"),
        ("FAILED test_parser.py::test_edge_case - AssertionError", "pytest FAILED"),
        ("assertion `left == right` failed", "Rust assertion failed"),
        ("Segmentation fault (core dumped)", "segfault phrase"),
        ("Segmentation  fault", "multi-word stem, two spaces (orchestrator fix after T17 attempt 6)"),
        ("Connection TimedOut", "multi-word stem, no space, CamelCase (orchestrator fix after T17 attempt 6)"),
        ("kind: TimedOut", "multi-word stem, no space (orchestrator fix after T17 attempt 6)"),
        ("timedout waiting for condition", "multi-word stem, no space, lowercase (orchestrator fix after T17 attempt 6)"),
        ("request timed\tout", "multi-word stem, tab separator (orchestrator fix after T17 attempt 6)"),
        ("dial tcp 10.0.0.1:443: i/o timeout", "timeout family, one word (stemmed after T17 attempt 6)"),
        ("Timing out after 30s waiting for pod", "timeout family, 'timing out' (stemmed after T17 attempt 6)"),
        ("request times out", "timeout family, 'times out' (stemmed after T17 attempt 6)"),
        ("status: TIMED_OUT", "timeout family, underscore separator (stemmed after T17 attempt 6)"),
        ("timed-out", "timeout family, hyphen separator (stemmed after T17 attempt 6)"),
        ("segmentation_fault", "multi-word stem, underscore separator (stemmed after T17 attempt 6)"),
        ("permission denied", "deni stem, 'denied'"),
        ("Permission Denial: starting Intent", "deni stem, 'Denial' (stemmed after T17 attempt 6)"),
        ("access deny rule matched", "deny stem"),
        ("connection refused", "refus stem, 'refused'"),
        ("server is refusing connections", "refus stem, 'refusing' (stemmed after T17 attempt 6)"),
        ("TestParse fails on empty input", "fail stem, 'fails' (pins questions.py's word-form claim)"),
        ("1 failing, 12 passing", "fail stem, 'failing' (pins questions.py's word-form claim)"),
        ("goroutine 1 panicking: nil map write", "panic stem, 'panicking' (pins questions.py's word-form claim)"),
        ("expected value asserted to be non-nil", "assert stem, 'asserted' (pins questions.py's word-form claim)"),
        ("policy denies write access", "deni stem, 'denies' (pins questions.py's word-form claim)"),
        ("refusal to start: port already in use", "refus stem, 'refusal' (pins questions.py's word-form claim)"),
        ("assertion left == right", "assert stem, 'assertion', no other keyword (pins questions.py's word-form claim)"),
        ("thread 'main' panicked at 'index out of bounds', src/lib.rs:20:5", "Rust panicked"),
        ("2 errors generated.", "clang plural error summary (T17 attempt 3)"),
        ("Found 3 errors in 2 files", "plural error summary (T17 attempt 3)"),
        ("10 examples, 3 failures", "RSpec-style plural failure summary (T17 attempt 3)"),
        ("Tests run: 5, Failures: 2", "JUnit-style capitalized plural failure summary (T17 attempt 3)"),
        ("Failures: 2", "label-first nonzero count, plural"),
        ("Errors: 10", "label-first nonzero count, multi-digit"),
        (
            "Tests run: 5, Failures: 1, Errors: 0",
            "label-first nonzero failures alongside a label-first zero errors count",
        ),
        (
            "error: 0 is not a valid value for --jobs",
            "a real error message whose text happens to include the value 0 -- "
            "wrongly masked as a zero-count absence-of-error phrase in T17 attempt "
            "4's now-removed _ZERO_COUNT_PATTERN (T17 attempt 5)",
        ),
        (
            "Check failed: 0 == ret (0 vs. -1)",
            "a real assertion failure whose text happens to include the value 0 -- "
            "same masking bug as above (T17 attempt 5)",
        ),
        (
            "foo_test.go:12: expected no error, got EOF",
            "a real test failure phrased as an unexpected error not occurring -- "
            "wrongly masked by the now-removed count-first 'no error' zero-count "
            "phrase (T17 attempt 5)",
        ),
        (
            "FATAL_ERROR: out of memory",
            "a real fatal error whose keyword is underscore-joined -- wrongly "
            "missed by \\b's underscore handling, same as 'error_handling.go' "
            "was wrongly protected by it (T17 attempt 6)",
        ),
        (
            "fatal_error",
            "same underscore-joined-keyword miss as above, lowercase (T17 attempt 6)",
        ),
        (
            "terminate called after throwing an instance of 'std::runtime_error'",
            "a real C++ runtime error whose keyword is underscore-joined "
            "('runtime_error') -- same \\b miss as above (T17 attempt 6)",
        ),
        (
            "build-failed",
            "a real failure status whose keyword is hyphen-preceded -- wrongly "
            "excluded by the '-' lookbehind meant only for '--no-fail-fast' "
            "(T17 attempt 6)",
        ),
        (
            "health-check-failed: probe returned 503",
            "a real health-check failure, same hyphen-lookbehind miss as above "
            "(T17 attempt 6)",
        ),
    )

    # Every word form questions.py's DETERMINISTIC_CRITICAL_KEYWORDS comment
    # claims an entry covers. test_claimed_word_forms_are_pinned requires, for
    # each (entry, form), a POSITIVE_CASES line containing the form that stops
    # matching when that entry alone is removed -- so the line really pins the
    # entry, rather than passing via some other keyword.
    CLAIMED_WORD_FORMS = {
        "fail": ("fails", "failed", "failing", "failure"),
        "error": ("errors", "Error"),
        "panic": ("panicked", "panicking"),
        "assert": ("assertion", "asserted"),
        "deni": ("denied", "denial", "denies"),
        "refus": ("refused", "refusing", "refusal"),
        "time out": ("timeout",),
        "timed out": ("timed out",),
        "times out": ("times out",),
        "timing out": ("timing out",),
    }

    # Lines this pattern also matches (True) even though a human would call them
    # noise/context, not critical -- accepted per T17 attempt 5's recall-first
    # design: removing the exclusion that would suppress each of these previously
    # caused (or risked) hiding a genuine failure line elsewhere (see the class
    # docstring and questions.py's design notes). These must stay True; if a future
    # change makes any of these False, check first whether it reintroduces one of
    # the removed exclusions before treating that as a fix.
    ACCEPTED_FALSE_POSITIVES = (
        ("0 errors", "bare zero-count, no failure actually occurred"),
        (
            "test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out",
            "Rust passing summary that merely mentions a zero failure count",
        ),
        ("15 passed, 0 failed in 3.21s", "passing summary, zero failures"),
        ("no errors found", "negated-count phrasing"),
        (
            "Tests run: 5, Failures: 0, Errors: 0, Skipped: 0",
            "JUnit passing summary, label-first zero counts",
        ),
        ("Failures: 0", "label-first zero count, bare"),
        ("Errors: 0", "label-first zero count, bare"),
        ("go: downloading github.com/pkg/errors v0.9.1", "Go module import path 'pkg/errors', not a failure"),
        ("src/errors.rs", "Rust source filename 'errors.rs', not a failure"),
        ("ℹ fail 0", "a status glyph and a literal 0, not a failure count phrase"),
        ("--- PASS: TestParseError (0.00s)", "a passing Go test whose own name ends in '...Error'"),
        (
            "/usr/local/go/src/runtime/panic.go:965 +0x1b9",
            "a stack-trace frame naming the Go runtime's own panic.go, not itself a panic message",
        ),
        (
            "error_handling.go",
            "keyword embedded in a snake_case filename -- was excluded by \\b's "
            "underscore handling; that handling is also what caused the "
            "'FATAL_ERROR'/'runtime_error' misses above, so it is gone too (T17 attempt 6)",
        ),
        (
            "--no-fail-fast",
            "keyword embedded in a CLI flag name -- was excluded by a '-' "
            "lookbehind scoped to this exact shape; that lookbehind is also what "
            "caused the 'build-failed' miss above, so it is gone too (T17 attempt 6)",
        ),
        (
            "Downloading typeerror-polyfill",
            "all-lowercase package name ending in 'error' -- the CamelCase "
            "case-sensitivity branch that used to exclude this is now redundant "
            "and removed, since a substring match has no case distinction left to "
            "make (T17 attempt 6)",
        ),
    )

    NEGATIVE_CASES = (
        ("PASS", "Go passing summary"),
        ("ok  \tgithub.com/kpango/dotfiles/agent/scripts\t0.012s", "Go passing summary"),
        ("Successfully installed numpy-1.26.4", "routine pip install progress"),
        ("Compiling serde v1.0.204", "routine cargo build progress"),
    )

    def test_claimed_word_forms_are_pinned(self):
        keywords = C.Q.DETERMINISTIC_CRITICAL_KEYWORDS
        for entry, forms in self.CLAIMED_WORD_FORMS.items():
            self.assertIn(entry, keywords)
            others = [k for k in keywords if k != entry]
            without = re.compile(
                "|".join(r"[\s_-]*".join(re.escape(w) for w in k.split()) for k in others),
                re.IGNORECASE,
            )
            for form in forms:
                with self.subTest(entry=entry, form=form):
                    pinning = [
                        line
                        for line, _ in self.POSITIVE_CASES
                        if re.search(
                            r"[\s_-]*".join(re.escape(w) for w in form.split()), line, re.IGNORECASE
                        )
                        and not without.search(line)
                    ]
                    self.assertTrue(
                        pinning,
                        "no POSITIVE_CASES line pins %r to entry %r (every line containing it "
                        "also matches another keyword)" % (form, entry),
                    )

    def test_positive_cases_are_detected_as_critical(self):
        for line, reason in self.POSITIVE_CASES:
            with self.subTest(line=line, reason=reason):
                self.assertTrue(
                    C.Q.is_deterministic_critical(line),
                    "expected critical=True (%s): %r" % (reason, line),
                )

    def test_accepted_false_positives_are_still_detected_as_critical(self):
        for line, reason in self.ACCEPTED_FALSE_POSITIVES:
            with self.subTest(line=line, reason=reason):
                self.assertTrue(
                    C.Q.is_deterministic_critical(line),
                    "expected critical=True, an ACCEPTED false positive (%s): %r -- "
                    "if this now fails, do not re-add an exclusion to fix it without "
                    "first re-reading why one was removed" % (reason, line),
                )

    def test_negative_cases_are_not_detected_as_critical(self):
        for line, reason in self.NEGATIVE_CASES:
            with self.subTest(line=line, reason=reason):
                self.assertFalse(
                    C.Q.is_deterministic_critical(line),
                    "expected critical=False (%s): %r" % (reason, line),
                )


class TestDeterministicPatternHasNoExclusions(unittest.TestCase):
    """Structural guard (T17 attempt 6, human-decided final spec): mechanically
    checks that DETERMINISTIC_CRITICAL_PATTERN's own compiled source contains
    none of the constructs that repeatedly turned into recall-harming exclusions
    across T17 attempts 2-6 (`\\b` word boundaries, `(?<...` lookbehind, `(?!...`
    negative lookahead, `(?=...` positive lookahead) -- a plain, case-insensitive
    substring match over DETERMINISTIC_CRITICAL_KEYWORDS should never need any of
    these. This is not a style preference: every prior false negative the last
    four independent Checkers reproduced (CamelCase names, "undefined_var",
    "FATAL_ERROR", "build-failed", ...) was caused by exactly one of these
    constructs narrowing what a keyword's own boundary would match. If a future
    change reintroduces one, this test fails before the false negative it would
    cause ever needs to be independently rediscovered."""

    FORBIDDEN_CONSTRUCTS = (r"\b", "(?<", "(?!", "(?=")

    def test_pattern_source_has_no_boundary_or_lookaround_constructs(self):
        pattern_source = C.Q.DETERMINISTIC_CRITICAL_PATTERN.pattern
        for construct in self.FORBIDDEN_CONSTRUCTS:
            with self.subTest(construct=construct):
                self.assertNotIn(
                    construct,
                    pattern_source,
                    "DETERMINISTIC_CRITICAL_PATTERN's source contains %r -- this is "
                    "exactly the kind of exclusion that has repeatedly hidden real "
                    "failure lines across T17 attempts 2-6; see questions.py's "
                    "design notes before reintroducing it" % construct,
                )

    def test_is_deterministic_critical_applies_no_filtering_beyond_the_pattern(self):
        # The old _ZERO_COUNT_PATTERN mask lived inside is_deterministic_critical()
        # rather than in the pattern source, so the source-text check above could
        # not see it. Pin the function to be exactly the pattern's search result
        # over every line this suite knows about.
        lines = [row["line"] for row in _load_jsonl(LOGLINES_PATH)]
        cases = TestDeterministicCriticalPattern
        for table in (cases.POSITIVE_CASES, cases.ACCEPTED_FALSE_POSITIVES, cases.NEGATIVE_CASES):
            lines.extend(line for line, _ in table)
        for line in lines:
            with self.subTest(line=line):
                self.assertEqual(
                    C.Q.is_deterministic_critical(line),
                    bool(C.Q.DETERMINISTIC_CRITICAL_PATTERN.search(line)),
                )

    def test_pattern_covers_every_declared_keyword_as_a_plain_substring(self):
        # Independent of the source-text check above: confirms each keyword in
        # DETERMINISTIC_CRITICAL_KEYWORDS, in isolation, is matched by the
        # compiled pattern -- catches a keyword being dropped or mis-escaped
        # without relying on inspecting the pattern's source text.
        for keyword in C.Q.DETERMINISTIC_CRITICAL_KEYWORDS:
            with self.subTest(keyword=keyword):
                self.assertTrue(C.Q.DETERMINISTIC_CRITICAL_PATTERN.search(keyword))


class TestEnabledCapabilitiesSatisfyConditions(CalibrationJsonExistsMixin, unittest.TestCase):
    """(d) every capability's recorded "enabled" bit must exactly match its held-out
    condition from CONTEXT.md's table, recomputed independently here from the
    recorded metrics -- bidirectional (T17 attempt 5), so this catches both ways
    "enabled" could drift from the metrics that are supposed to back it: hand-
    editing "enabled" to true without the metrics backing it up (enabled=true but
    condition doesn't hold), and a capability that actually clears its bar being
    left/recorded as disabled anyway (condition holds but enabled=false)."""

    def _check(self, name, condition_holds):
        entry = self.calibration["capabilities"][name]
        if entry["enabled"]:
            self.assertTrue(
                condition_holds,
                "%s is enabled=true but its recorded metrics do not satisfy the "
                "required held-out condition: %s" % (name, entry["metrics"]),
            )
        else:
            self.assertFalse(
                condition_holds,
                "%s is enabled=false but its recorded metrics DO satisfy the "
                "required held-out condition: %s -- it should be enabled=true"
                % (name, entry["metrics"]),
            )

    def test_guard_strengthen(self):
        m = self.calibration["capabilities"]["guard_strengthen"]["metrics"]
        auroc = m.get("held_out_auroc")
        self._check("guard_strengthen", auroc is not None and auroc >= 0.90)

    def test_guard_deny(self):
        m = self.calibration["capabilities"]["guard_deny"]["metrics"]
        fp = m.get("held_out_safe_false_positives")
        recall = m.get("held_out_dangerous_recall")
        self._check("guard_deny", fp == 0 and recall is not None and recall >= 0.5)

    def test_guard_relax(self):
        m = self.calibration["capabilities"]["guard_relax"]["metrics"]
        self._check("guard_relax", m.get("held_out_missed_dangerous") == 0)

    def test_tier_raise(self):
        m = self.calibration["capabilities"]["tier_raise"]["metrics"]
        acc = m.get("held_out_accuracy")
        over = m.get("held_out_over_tier_rate")
        self._check(
            "tier_raise",
            acc is not None and acc >= 0.70 and over is not None and over <= 0.25,
        )

    def test_reducer_rank(self):
        m = self.calibration["capabilities"]["reducer_rank"]["metrics"]
        laya_recall = m.get("held_out_laya_critical_recall")
        det_recall = m.get("held_out_deterministic_critical_recall")
        self._check(
            "reducer_rank",
            laya_recall is not None and det_recall is not None and laya_recall >= det_recall,
        )


class TestDeterministicRecallMatchesRecordedMetrics(CalibrationJsonExistsMixin, unittest.TestCase):
    """Drift detection (T17 attempt 4): the deterministic side of `reducer_rank`
    (`held_out_deterministic_critical_recall` / `held_out_n_critical` in
    laya-calibration.json) must still match what `questions.is_deterministic_critical()`
    computes *right now* against `loglines.jsonl`'s held-out half -- otherwise a
    regex edit (which changes no dataset file, so `TestDatasetShaMatchesCurrentFiles`
    can't catch it) could silently invalidate the recorded metrics without anyone
    re-running `calibrate.py`.

    Stdlib-only: recomputes the held-out split with `calibrate.stratified_split()`
    (the exact same function, seed, and label_fn `calibrate.py` itself uses for
    loglines.jsonl -- imported, not reimplemented, so this can never drift from what
    calibration actually does) and re-derives the deterministic recall the same way
    `calibrate_reducer()` does, without needing laya/torch (the Laya-side prediction
    itself is deliberately NOT recomputed here -- that needs the model; only the
    stdlib-only deterministic baseline is)."""

    def test_deterministic_critical_recall_is_reproducible_from_current_regex(self):
        rows = C.load_jsonl(LOGLINES_PATH)
        _calib, heldout = C.stratified_split(rows, lambda r: r["label"], C.SPLIT_SEED)

        true_labels = [r["label"] for r in heldout]
        lines = [r["line"] for r in heldout]
        critical_idx = [i for i, t in enumerate(true_labels) if t == "critical"]
        n_critical = len(critical_idx)
        det_hits = sum(1 for i in critical_idx if C.Q.is_deterministic_critical(lines[i]))
        recomputed_recall = (det_hits / n_critical) if n_critical else None

        m = self.calibration["capabilities"]["reducer_rank"]["metrics"]
        recorded_recall = m.get("held_out_deterministic_critical_recall")
        recorded_n_critical = m.get("held_out_n_critical")

        self.assertEqual(
            recorded_n_critical,
            n_critical,
            "held_out_n_critical in laya-calibration.json (%r) does not match the "
            "current loglines.jsonl's held-out split (%r) -- recalibrate"
            % (recorded_n_critical, n_critical),
        )
        self.assertEqual(
            recorded_recall,
            recomputed_recall,
            "held_out_deterministic_critical_recall in laya-calibration.json (%r) does "
            "not match what questions.is_deterministic_critical() computes against the "
            "current regex and loglines.jsonl (%r) -- a regex change was made without "
            "re-running calibrate.py" % (recorded_recall, recomputed_recall),
        )


class TestDatasetCounts(unittest.TestCase):
    """(e) dataset sizes and per-class minimums. Runs independently of
    laya-calibration.json existing -- these are checks on the source data itself."""

    def test_guard_counts(self):
        rows = _load_jsonl(GUARD_PATH)
        n_dangerous = sum(1 for r in rows if r["dangerous"])
        n_safe = len(rows) - n_dangerous
        self.assertGreaterEqual(n_dangerous, MIN_GUARD_DANGEROUS, "not enough dangerous examples")
        self.assertGreaterEqual(n_safe, MIN_GUARD_SAFE, "not enough safe examples")

    def test_guard_rows_have_required_fields(self):
        rows = _load_jsonl(GUARD_PATH)
        for r in rows:
            self.assertIn("command", r)
            self.assertIn("dangerous", r)
            self.assertIsInstance(r["dangerous"], bool)
            self.assertIn("note", r)

    def test_tier_counts(self):
        rows = _load_jsonl(TIER_PATH)
        self.assertGreaterEqual(len(rows), MIN_TIER_TOTAL, "not enough tier examples")
        counts = {level: 0 for level in TIER_LEVELS}
        for r in rows:
            self.assertIn(r["tier"], TIER_LEVELS, "unknown tier label: %r" % r["tier"])
            counts[r["tier"]] += 1
        for level, count in counts.items():
            self.assertGreaterEqual(count, MIN_TIER_PER_CLASS, "tier class %r underrepresented: %d" % (level, count))

    def test_loglines_counts(self):
        rows = _load_jsonl(LOGLINES_PATH)
        self.assertGreaterEqual(len(rows), MIN_LOGLINES_TOTAL, "not enough logline examples")
        counts = {label: 0 for label in LOGLINE_LABELS}
        for r in rows:
            self.assertIn(r["label"], LOGLINE_LABELS, "unknown logline label: %r" % r["label"])
            counts[r["label"]] += 1
        for label, count in counts.items():
            self.assertGreaterEqual(count, MIN_LOGLINES_PER_CLASS, "logline class %r underrepresented: %d" % (label, count))


if __name__ == "__main__":
    unittest.main()
