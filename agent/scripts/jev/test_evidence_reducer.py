"""Regression tests for agent/scripts/jev/evidence_reducer.py (T11, CONTEXT.md
"ai-env-deepresearch-overhaul" I-5). Fully offline, same MockLayaServer as
test_guard_advisor.py. Every "reducer_rank enabled" fixture carries a matching
revision + Dockerfile pair -- see test_guard_advisor.py's module docstring."""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TEST_DIR)

import evidence_reducer  # noqa: E402
import questions  # noqa: E402
from test_support_mock_laya import MockLayaServer  # noqa: E402
from test_support_revision_fixture import (  # noqa: E402
    TEST_REVISION,
    write_dockerfile,
    _RevisionFixtureMixin,
)


def _write_reducer_calibration(reducer_rank_enabled, revision=TEST_REVISION):
    data = {"capabilities": {"reducer_rank": {"enabled": reducer_rank_enabled}}}
    if revision is not None:
        data["revision"] = revision
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    return path


def _make_log(n_lines, critical_at=()):
    lines = []
    for i in range(n_lines):
        if i in critical_at:
            lines.append("line %d: FATAL ERROR something broke" % i)
        else:
            lines.append("line %d: routine progress output padding padding" % i)
    return "\n".join(lines)


# evidence_reducer.py's default save_dir (_save_full_text, when no explicit
# save_dir is passed) is `~/.claude/session-data/evidence-reducer/<session_id>`,
# resolved via os.path.expanduser("~") -- i.e. the REAL developer $HOME unless
# something overrides HOME for the process. Every test in this module that
# exercises evidence_reducer.py's main() as a real subprocess (TestFailOpenAt
# HookLevel) must set HOME to a throwaway tempdir for that reason. This
# snapshot/tearDownModule pair is the regression guard for that invariant --
# mirrors test_decide_integration.py's TestProductionFilesNeverMutated
# module-import-time-snapshot pattern, but as a module-level fixture
# (tearDownModule always runs once, after every test in this module has run,
# regardless of unittest's alphabetical class/method ordering) so it catches a
# leak from ANY test here, not only ones that happen to run before it.
#
# Checker-reported (revision 2 review): snapshotting the WHOLE evidence-reducer/
# tree would false-positive on a concurrently running, unrelated session's own
# hook writing there after the merge. Scoped instead to just the session_id
# subdirectories THIS FILE's tests actually pass -- confirmed via
# `grep -n session_id= test_evidence_reducer.py`, currently only "s1" -- add a
# new value here if a future test starts using one.
_SESSION_IDS_USED_BY_THIS_FILE = ("s1",)

_REAL_HOME_REDUCER_DIRS = tuple(
    os.path.join(os.path.expanduser("~"), ".claude", "session-data", "evidence-reducer", sid)
    for sid in _SESSION_IDS_USED_BY_THIS_FILE
)


def _snapshot_real_home_reducer_dirs():
    seen = set()
    for reducer_dir in _REAL_HOME_REDUCER_DIRS:
        if not os.path.isdir(reducer_dir):
            continue
        for dirpath, _dirnames, filenames in os.walk(reducer_dir):
            for name in filenames:
                path = os.path.join(dirpath, name)
                seen.add((path, os.stat(path).st_mtime_ns))
    return frozenset(seen)


_REAL_HOME_SNAPSHOT_AT_IMPORT = _snapshot_real_home_reducer_dirs()


def tearDownModule():
    after = _snapshot_real_home_reducer_dirs()
    if after != _REAL_HOME_SNAPSHOT_AT_IMPORT:
        raise AssertionError(
            "a test in test_evidence_reducer.py wrote into one of the REAL %r "
            "(before=%r after=%r) -- every subprocess call through "
            "evidence_reducer.py's main() must override HOME, as "
            "TestFailOpenAtHookLevel.setUp does"
            % (
                _REAL_HOME_REDUCER_DIRS,
                sorted(_REAL_HOME_SNAPSHOT_AT_IMPORT),
                sorted(after),
            )
        )


class TestBelowThresholdIsUntouched(unittest.TestCase):
    def test_short_text_returned_as_same_object(self):
        text = "short output\nline2\n"
        out, saved = evidence_reducer.reduce_text(text, session_id="s1", stream_name="stdout")
        self.assertIs(out, text)
        self.assertIsNone(saved)

    def test_few_lines_even_if_long_is_untouched(self):
        text = "\n".join(["x" * 500] * 10)
        self.assertGreaterEqual(len(text), evidence_reducer.REDUCER_MIN_CHARS)
        out, saved = evidence_reducer.reduce_text(text, session_id="s1", stream_name="stdout")
        self.assertIs(out, text)
        self.assertIsNone(saved)


class TestReductionPreservesCriticalAndOrder(_RevisionFixtureMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.tmpdir = tempfile.mkdtemp()
        self.calib_disabled = _write_reducer_calibration(False)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)
        os.unlink(self.calib_disabled)
        super().tearDown()

    def _reduce(self, text):
        return evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_disabled, save_dir=self.tmpdir,
            dockerfile_path=self.dockerfile_path,
        )

    def test_critical_lines_always_kept_deterministic_only(self):
        text = _make_log(200, critical_at={50, 150})
        out, saved = self._reduce(text)
        self.assertIsNot(out, text)
        self.assertIn("line 50: FATAL ERROR something broke", out)
        self.assertIn("line 150: FATAL ERROR something broke", out)
        self.assertTrue(questions.is_deterministic_critical("FATAL ERROR"))

    def test_go_test_failure_assertion_detail_line_is_kept(self):
        """T15 regression: `--- FAIL: ...` matches is_deterministic_critical()
        (via the "fail" keyword), but Go's own assertion-detail line right
        after it -- the line a developer actually needs -- contains no
        keyword at all and would otherwise fall to the reducer_rank budget
        (or be dropped entirely with reducer_rank disabled, as here)."""
        lines = ["line %d: routine progress output padding padding" % i for i in range(300)]
        lines[150] = "--- FAIL: TestSearch (0.03s)"
        lines[151] = "    main_test.go:88: expected 3 results, got 2"
        text = "\n".join(lines)
        self.assertFalse(questions.is_deterministic_critical(lines[151]))
        out, saved = self._reduce(text)
        self.assertIn("--- FAIL: TestSearch (0.03s)", out)
        self.assertIn("    main_test.go:88: expected 3 results, got 2", out)

    def test_rust_error_location_arrow_line_is_kept(self):
        """T15 regression: Rust's `error[E0382]: ...` matches via the "error"
        keyword, but the `-->` location line right after it carries no
        keyword of its own."""
        lines = ["line %d: routine progress output padding padding" % i for i in range(300)]
        lines[150] = "error[E0382]: use of moved value: `x`"
        lines[151] = "  --> src/main.rs:12:5"
        text = "\n".join(lines)
        self.assertFalse(questions.is_deterministic_critical(lines[151]))
        out, saved = self._reduce(text)
        self.assertIn("error[E0382]: use of moved value: `x`", out)
        self.assertIn("  --> src/main.rs:12:5", out)

    def test_critical_context_lines_constant_is_2_and_third_line_after_is_dropped(self):
        """Checker-requested (revision 2 review): pins CRITICAL_CONTEXT_LINES's
        value directly, so a future change to it forces an update here instead
        of drifting silently. Also confirms the floor doesn't widen without
        bound: the 3rd line after a critical line -- with no keyword of its
        own and outside head/tail -- must NOT be kept."""
        self.assertEqual(evidence_reducer.CRITICAL_CONTEXT_LINES, 2)
        lines = ["line %d: routine progress output padding padding" % i for i in range(300)]
        lines[100] = "--- FAIL: TestSearch (0.03s)"
        lines[101] = "CONTEXT_LINE_1_UNIQUE_MARKER"
        lines[102] = "CONTEXT_LINE_2_UNIQUE_MARKER"
        lines[103] = "CONTEXT_LINE_3_UNIQUE_MARKER_MUST_BE_DROPPED"
        text = "\n".join(lines)
        out, saved = self._reduce(text)
        self.assertIn("CONTEXT_LINE_1_UNIQUE_MARKER", out)
        self.assertIn("CONTEXT_LINE_2_UNIQUE_MARKER", out)
        self.assertNotIn("CONTEXT_LINE_3_UNIQUE_MARKER_MUST_BE_DROPPED", out)

    def test_output_lines_are_a_subsequence_in_original_order(self):
        text = _make_log(300, critical_at={10, 20, 290})
        out, saved = self._reduce(text)
        original_lines = text.split("\n")
        out_lines = out.split("\n")
        marker = out_lines[-1]
        self.assertTrue(marker.startswith("[evidence-reducer: kept"))
        kept_lines = out_lines[:-1]
        idx = 0
        for kept in kept_lines:
            found = False
            while idx < len(original_lines):
                if original_lines[idx] == kept:
                    found = True
                    idx += 1
                    break
                idx += 1
            self.assertTrue(found, "kept line not found in order: %r" % kept)

    def test_no_generated_text_every_kept_line_is_verbatim_original(self):
        text = _make_log(150, critical_at={5, 100})
        out, saved = self._reduce(text)
        original_set = set(text.split("\n"))
        out_lines = out.split("\n")
        for line in out_lines[:-1]:
            self.assertIn(line, original_set)

    def test_head_and_tail_are_kept(self):
        text = _make_log(200)
        out, saved = self._reduce(text)
        original_lines = text.split("\n")
        for i in range(evidence_reducer.HEAD_LINES):
            self.assertIn(original_lines[i], out)
        for i in range(len(original_lines) - evidence_reducer.TAIL_LINES, len(original_lines)):
            self.assertIn(original_lines[i], out)

    def test_full_text_saved_with_0600_permissions(self):
        text = _make_log(200, critical_at={5})
        out, saved = self._reduce(text)
        self.assertIsNotNone(saved)
        self.assertTrue(os.path.exists(saved))
        mode = stat.S_IMODE(os.stat(saved).st_mode)
        self.assertEqual(mode, 0o600)
        with open(saved, encoding="utf-8") as f:
            self.assertEqual(f.read(), text)

    def test_marker_references_the_actually_saved_path(self):
        text = _make_log(200, critical_at={5})
        out, saved = self._reduce(text)
        self.assertIn(saved, out)


class TestSaveFailureAbortsReduction(unittest.TestCase):
    def test_unwritable_save_dir_returns_text_unchanged(self):
        text = _make_log(200, critical_at={5})
        calib = _write_reducer_calibration(False)
        bogus_dir = "/nonexistent-root-dir-xyz/definitely/not/writable"
        try:
            out, saved = evidence_reducer.reduce_text(
                text, session_id="s1", stream_name="stdout",
                calibration_file=calib, save_dir=bogus_dir,
            )
            self.assertIs(out, text)
            self.assertIsNone(saved)
        finally:
            os.unlink(calib)


class TestSessionIdSanitization(unittest.TestCase):
    """T15 (Checker-reported path-traversal gap): session_id currently comes
    from a Tier-B shim's CLAUDE_SESSION_ID env var and, in the future, may
    come from hook JSON input -- neither is validated upstream. It is only
    ever interpolated into a path in the DEFAULT save_dir branch of
    _save_full_text (every other test in this file passes an explicit
    save_dir=, which bypasses session_id entirely) -- so this patches
    os.path.expanduser("~") to a throwaway tempdir standing in for the real
    home, exercising that exact default-save_dir code path (including
    evidence_reducer._sanitize_session_id) without ever touching the real
    home directory.

    Checker-reported (revision 3 review): checking ONLY that the saved path
    stays confined is not enough -- the original `.match()` against a
    `$`-anchored pattern let "abc\\n" through as if it equalled "abc" (Python's
    `$` also matches immediately before a single trailing newline), which
    still would have stayed "confined" (as a literal "abc\\n"-named directory
    under evidence-reducer/) while silently NOT being sanitized to "unknown"
    at all. So every case here is checked two ways: (1) directly, that
    `_sanitize_session_id()` returns the EXACT literal string "unknown", and
    (2) end-to-end, that the resulting saved path still stays confined
    (belt-and-suspenders -- (1) alone could theoretically pass while some
    other code path bypassed _sanitize_session_id entirely)."""

    # Confirmed by mutation testing against the pre-fix `.match()` version:
    # "abc\n", "..\n", ".\n", and "\n" all returned themselves VERBATIM
    # (not "unknown") because trailing "\n" satisfied the `$` anchor under
    # `.match()`. "abc\r"/"abc\t"/"has space" are additional non-newline
    # control/whitespace cases the same allow-list must also still reject.
    #
    # Checker-reported (revision 4 review): the cases above didn't cover
    # non-ASCII input or the exact length boundary, so three further
    # mutations all passed this suite unnoticed: (M6) widening the allow-list
    # regex to `[\w.-]+` (Python's `\w` matches Unicode letters/digits from
    # ANY script, not just ASCII); (M7) loosening _SESSION_ID_MAX_LEN to 199;
    # (M9) deleting the `not session_id` (empty-string) check. "é" (accented
    # Latin), "ａｂｃ" (fullwidth Latin), and "٣" (Arabic-Indic digit) are all
    # `\w` but none are in this module's ASCII-only [A-Za-z0-9._-] allow-list
    # -- they catch M6. "x" * 129 is one character past _SESSION_ID_MAX_LEN
    # (128) but still well under M7's 199, and is otherwise a fully valid
    # ASCII allow-listed string -- it catches M7 specifically (see the
    # boundary test below for the "x" * 128, still-valid counterpart). ""
    # catches M9 in principle, though `.fullmatch()`'s `+` quantifier already
    # independently rejects an empty string regardless of the `not
    # session_id` check (confirmed by mutation testing below) -- included
    # anyway because the empty-string case itself is a requirement, not
    # merely a mutation-kill.
    MALICIOUS_SESSION_IDS = (
        "../x",
        "/etc",
        "a/b",
        "..",
        ".",
        "a\x00b",
        "x" * 200,
        "x" * 129,
        "abc\n",
        "..\n",
        ".\n",
        "\n",
        "abc\r",
        "abc\t",
        "has space",
        "",
        "é",
        "ａｂｃ",
        "٣",
    )

    def setUp(self):
        self.fake_home = tempfile.mkdtemp()
        self.calib_disabled = _write_reducer_calibration(False)
        real_expanduser = os.path.expanduser
        self._patcher = mock.patch(
            "os.path.expanduser",
            side_effect=lambda p, _real=real_expanduser, _fake=self.fake_home: (
                _fake if p == "~" else _real(p)
            ),
        )
        self._patcher.start()

    def tearDown(self):
        self._patcher.stop()
        shutil.rmtree(self.fake_home, ignore_errors=True)
        os.unlink(self.calib_disabled)

    def _expected_root(self):
        return os.path.realpath(
            os.path.join(self.fake_home, ".claude", "session-data", "evidence-reducer")
        )

    def _save(self, session_id, stream_name="stdout"):
        text = _make_log(200, critical_at={5})
        out, saved = evidence_reducer.reduce_text(
            text, session_id=session_id, stream_name=stream_name,
            calibration_file=self.calib_disabled,
            # save_dir intentionally omitted -- exercises the default (session_id
            # -interpolating) save_dir branch this test targets.
        )
        self.assertIsNotNone(saved, "expected save to succeed for session_id=%r" % (session_id,))
        return saved

    def _assert_confined(self, saved_path):
        root = self._expected_root()
        actual = os.path.realpath(saved_path)
        self.assertTrue(
            actual == root or actual.startswith(root + os.sep),
            "%r escaped %r" % (actual, root),
        )

    def test_malicious_session_ids_sanitize_to_exactly_unknown(self):
        for session_id in self.MALICIOUS_SESSION_IDS:
            with self.subTest(session_id=session_id):
                self.assertEqual(evidence_reducer._sanitize_session_id(session_id), "unknown")

    def test_malicious_session_ids_stay_confined_end_to_end(self):
        # Every malicious id here sanitizes to the SAME "unknown" directory, so
        # a distinct stream_name per iteration is needed: _save_full_text's
        # saved filename is only `<second-resolution timestamp>-<pid>-
        # <stream_name>.log`, and several of these subTest iterations run
        # within the same wall-clock second in the same process -- an
        # identical stream_name would collide on os.O_EXCL and (correctly,
        # but unhelpfully for this test) make the save fail for an unrelated
        # reason having nothing to do with sanitization.
        for i, session_id in enumerate(self.MALICIOUS_SESSION_IDS):
            with self.subTest(session_id=session_id):
                self._assert_confined(self._save(session_id, stream_name="stdout-%d" % i))

    def test_normal_uuid_is_preserved_verbatim(self):
        session_id = "550e8400-e29b-41d4-a716-446655440000"
        self.assertEqual(evidence_reducer._sanitize_session_id(session_id), session_id)
        saved = self._save(session_id)
        self._assert_confined(saved)
        self.assertEqual(
            os.path.dirname(os.path.realpath(saved)),
            os.path.join(self._expected_root(), session_id),
        )

    def test_max_length_boundary_is_preserved_verbatim(self):
        # Checker-requested (revision 4 review) boundary counterpart to
        # "x" * 129 (in MALICIOUS_SESSION_IDS, sanitized to "unknown"):
        # exactly _SESSION_ID_MAX_LEN (128) ASCII allow-listed characters is
        # NOT over the limit (`len(session_id) > _SESSION_ID_MAX_LEN` is
        # false at exactly 128) and must be preserved verbatim, not
        # sanitized -- pins the boundary from both sides.
        session_id = "x" * evidence_reducer._SESSION_ID_MAX_LEN
        self.assertEqual(len(session_id), 128)
        self.assertEqual(evidence_reducer._sanitize_session_id(session_id), session_id)
        saved = self._save(session_id)
        self._assert_confined(saved)
        self.assertEqual(
            os.path.dirname(os.path.realpath(saved)),
            os.path.join(self._expected_root(), session_id),
        )


class TestReducerRankFillsRemainingBudget(_RevisionFixtureMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.server = MockLayaServer()
        self.tmpdir = tempfile.mkdtemp()
        self.calib_enabled = _write_reducer_calibration(True)

    def tearDown(self):
        self.server.shutdown()
        shutil.rmtree(self.tmpdir, ignore_errors=True)
        os.unlink(self.calib_enabled)
        super().tearDown()

    def test_laya_scored_lines_fill_remaining_budget(self):
        # T18: candidates are now scanned TAIL-FIRST (last non-floor line
        # backward -- see reduce_text()'s own comment), and _rank_candidates
        # stops issuing new calls once LAYA_MAX_CALLS calls have been issued, so
        # the important line must fall within the LAST LAYA_MAX_CALLS candidates
        # (i.e. shortly before the TAIL_LINES floor) for this test to still
        # observe it being scored and kept. It must also be classified
        # "critical" via `probabilities` (argmax over REDUCER_LEVELS indices) --
        # T18: raw `score` alone no longer selects a line, only Laya's
        # "critical" classification does (questions.reducer_predicted_class()).
        # 200 lines: comfortably over both MAX_KEPT_LINES (40, or reduce_text()
        # no-ops as "already few enough") and REDUCER_MIN_CHARS (4096 chars,
        # or reduce_text() no-ops as "too short to bother").
        n_lines = 200
        important_idx = n_lines - evidence_reducer.TAIL_LINES - 1 - evidence_reducer.LAYA_MAX_CALLS // 2
        lines = ["line %d: routine noise" % i for i in range(n_lines)]
        lines[important_idx] = "line %d: the most important context line" % important_idx
        text = "\n".join(lines)

        def answer_fn(qid, q, req):
            line = req.get("state", {}).get(questions.REDUCER_STATE_KEY, "")
            if "most important" in line:
                return {"type": "score", "score": 2.0, "confidence": 0.9,
                        "probabilities": {"0": 0.0, "1": 0.0, "2": 1.0}}
            return {"type": "score", "score": 0.0, "confidence": 0.9,
                    "probabilities": {"0": 1.0, "1": 0.0, "2": 0.0}}

        self.server.answer_fn = answer_fn
        out, saved = evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_budget_ms=20000, dockerfile_path=self.dockerfile_path,
        )
        self.assertIn("the most important context line", out)
        self.assertGreater(len(self.server.requests), 0)

    def test_laya_disabled_never_calls_server(self):
        calib_disabled = _write_reducer_calibration(False)
        try:
            text = _make_log(200)
            out, saved = evidence_reducer.reduce_text(
                text, session_id="s1", stream_name="stdout",
                calibration_file=calib_disabled, save_dir=self.tmpdir,
                endpoint=self.server.url, dockerfile_path=self.dockerfile_path,
            )
            self.assertEqual(len(self.server.requests), 0)
        finally:
            os.unlink(calib_disabled)

    def test_revision_mismatch_never_calls_server(self):
        other_dir = tempfile.mkdtemp()
        try:
            mismatched = write_dockerfile(other_dir, "c" * 40)
            text = _make_log(200)
            out, saved = evidence_reducer.reduce_text(
                text, session_id="s1", stream_name="stdout",
                calibration_file=self.calib_enabled, save_dir=self.tmpdir,
                endpoint=self.server.url, dockerfile_path=mismatched,
            )
            self.assertEqual(len(self.server.requests), 0)
        finally:
            shutil.rmtree(other_dir, ignore_errors=True)

    def test_laya_budget_deadline_stops_further_calls(self):
        """A per-call delay large enough that the cumulative wall-clock budget is
        exhausted after a handful of calls must not block indefinitely -- later
        candidates are simply left unscored."""
        self.server.delay = 0.3
        text = _make_log(500)  # far more candidates than could fit at 0.3s/call
        out, saved = evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_budget_ms=1000, timeout=2000,
            dockerfile_path=self.dockerfile_path,
        )
        self.assertLess(len(self.server.requests), 20)

    def test_laya_max_calls_caps_call_count_even_with_ample_budget(self):
        """T18 perf-review finding: LAYA_MAX_CALLS is a device-independent
        ceiling on the number of Laya calls _rank_candidates issues, separate
        from the wall-clock deadline. With a generous budget and a fast
        (delay=0, the default) mock server, the deadline alone would let far
        more than LAYA_MAX_CALLS calls through -- this pins the count cap
        itself, not just its interaction with the deadline."""
        text = _make_log(300)  # far more remaining-budget candidates than LAYA_MAX_CALLS
        out, saved = evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_budget_ms=20000, timeout=2000,
            dockerfile_path=self.dockerfile_path,
        )
        self.assertEqual(len(self.server.requests), evidence_reducer.LAYA_MAX_CALLS)

    def test_large_explicit_timeout_is_capped_to_remaining_budget(self):
        """Checker-reported "軽微な点" (revision 2 review): passing `timeout=None`
        through to every call let a large configured timeout make a SINGLE
        in-flight call run past the shared deadline by that entire amount.
        Here an explicit timeout kwarg far larger than the budget (10000ms vs a
        1000ms budget) must not let the total wall-clock time approach 10s --
        `_rank_candidates` now caps each call's own timeout to
        `min(requested, remaining_until_deadline)`."""
        self.server.delay = 3.0  # the mock server would happily hold the connection this long if allowed to
        text = _make_log(300)
        start = time.monotonic()
        out, saved = evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_budget_ms=1000, timeout=10000,
            dockerfile_path=self.dockerfile_path,
        )
        elapsed_ms = (time.monotonic() - start) * 1000.0
        # Budget (1000ms) + generous slack for the capped call's own connect/
        # read overhead -- nowhere near the requested 10000ms timeout, which is
        # exactly the gap this fix closes.
        self.assertLess(elapsed_ms, 2500)

    def test_large_JEV_TIMEOUT_MS_env_var_is_also_capped_to_remaining_budget(self):
        """Same defect, but via the env-var path (`timeout=None` passed through,
        so `_rank_candidates` falls back to resolving `JEV_TIMEOUT_MS` itself)
        rather than an explicit `timeout=` kwarg."""
        self.server.delay = 3.0
        text = _make_log(300)
        old_env = os.environ.get("JEV_TIMEOUT_MS")
        os.environ["JEV_TIMEOUT_MS"] = "10000"
        try:
            start = time.monotonic()
            out, saved = evidence_reducer.reduce_text(
                text, session_id="s1", stream_name="stdout",
                calibration_file=self.calib_enabled, save_dir=self.tmpdir,
                endpoint=self.server.url, laya_budget_ms=1000, timeout=None,
                dockerfile_path=self.dockerfile_path,
            )
            elapsed_ms = (time.monotonic() - start) * 1000.0
            self.assertLess(elapsed_ms, 2500)
        finally:
            if old_env is None:
                os.environ.pop("JEV_TIMEOUT_MS", None)
            else:
                os.environ["JEV_TIMEOUT_MS"] = old_env

    def test_shared_deadline_across_two_reduce_text_calls_caps_combined_time(self):
        """Simulates main()'s own pattern: ONE shared `laya_deadline` computed
        once and passed to both a stdout and a stderr reduce_text() call. Total
        wall-clock time across BOTH calls must stay near the single budget, not
        double it (the bug this fix corrects: a per-call budget would let stdout
        alone spend up to laya_budget_ms, then stderr spend ANOTHER
        laya_budget_ms on top)."""
        self.server.delay = 0.3
        budget_ms = 1000
        shared_deadline = time.monotonic() + budget_ms / 1000.0
        text_a = _make_log(500)
        text_b = _make_log(500)

        start = time.monotonic()
        evidence_reducer.reduce_text(
            text_a, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_deadline=shared_deadline, timeout=2000,
            dockerfile_path=self.dockerfile_path,
        )
        evidence_reducer.reduce_text(
            text_b, session_id="s1", stream_name="stderr",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_deadline=shared_deadline, timeout=2000,
            dockerfile_path=self.dockerfile_path,
        )
        elapsed_ms = (time.monotonic() - start) * 1000.0
        # Budget (1000ms) + at most one in-flight call's own delay (300ms) + slack
        # for non-network overhead -- well under 2x the budget, which is what the
        # bug being tested for would have produced (each call independently
        # spending up to the full budget).
        self.assertLess(elapsed_ms, budget_ms + 900)

    def test_shared_calls_budget_across_two_reduce_text_calls_caps_total_calls(self):
        """T18 Checker finding: an earlier revision's LAYA_MAX_CALLS cap was a
        local counter inside `_rank_candidates`, reset on every `reduce_text()`
        call -- main()'s real pattern (ONE hook invocation, one `reduce_text()`
        call each for stdout and stderr) could therefore issue up to
        2*LAYA_MAX_CALLS calls total (measured: 16, with LAYA_MAX_CALLS=8), not
        LAYA_MAX_CALLS. Simulates that real pattern with a single SHARED
        `_CallBudget` object (mirroring the shared `laya_deadline` pattern in the
        test above and `main()`'s own real wiring) and asserts the COMBINED call
        count across both streams stays <= LAYA_MAX_CALLS."""
        budget_ms = 20000  # generous: only the call-count cap should bind here, not the deadline
        shared_deadline = time.monotonic() + budget_ms / 1000.0
        shared_calls_budget = evidence_reducer._CallBudget()
        text_a = _make_log(300)  # far more remaining-budget candidates than LAYA_MAX_CALLS, each
        text_b = _make_log(300)  # stream on its own

        evidence_reducer.reduce_text(
            text_a, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_deadline=shared_deadline, timeout=2000,
            calls_budget=shared_calls_budget, dockerfile_path=self.dockerfile_path,
        )
        evidence_reducer.reduce_text(
            text_b, session_id="s1", stream_name="stderr",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_deadline=shared_deadline, timeout=2000,
            calls_budget=shared_calls_budget, dockerfile_path=self.dockerfile_path,
        )
        self.assertLessEqual(len(self.server.requests), evidence_reducer.LAYA_MAX_CALLS)

    def test_zero_score_non_critical_lines_are_never_kept_via_ranking(self):
        """T18 Checker finding (3, and a follow-up gap caught in trial-2 review):
        a line must be classified "critical" (argmax over `probabilities`) to be
        added by the ranking pass -- a `score` value alone must not suffice, and
        conversely a non-critical classification must never be kept regardless
        of `score`. Every non-floor line here reports probabilities favoring
        "noise" (index 0); none of them may appear in the output beyond the
        unconditional head/tail floor.

        Score is 2.0, NOT the 99.0 an earlier revision of this test used:
        `jev_client._validate_answer()` requires a "score"-type answer's `score`
        to be in `0 <= score <= len(criteria) - 1` (== 2 for REDUCER_QUESTIONS'
        3-entry criteria list), so 99.0 fails validation and `evaluate()` returns
        None for every single call -- `_rank_candidates`'s `if answer is None:
        continue` then skips straight past the "is it critical" check this test
        means to exercise, without ever reaching it. Confirmed vacuous: with
        score=99.0, `if predicted != "critical": continue` mutated to `if False:
        continue` (i.e. every scored candidate treated as critical and kept)
        still made this test PASS, because no candidate was ever scored at all.
        2.0 is a valid, non-degenerate score (the top of the ordered noise=0/
        context=1/critical=2 scale) paired with a probabilities dict that still
        classifies "noise" -- deliberately decoupling `score`'s value from the
        classification, so a regression that reads `score` instead of
        `probabilities` is caught by BOTH this test's exactness check and
        `test_laya_scored_lines_fill_remaining_budget`'s different-shaped fixture.

        Compares the exact SET of kept lines (not just a count) against the
        exact floor, so a bug that swapped in different non-floor lines at the
        same count would also be caught."""
        n_lines = 200
        lines = ["line %d: routine noise" % i for i in range(n_lines)]
        text = "\n".join(lines)

        def answer_fn(qid, q, req):
            # Valid score (2.0, the "critical" end of the scale) but classified
            # "noise" via probabilities (index 0 highest) -- must NOT be kept:
            # criticality, not score, selects a line.
            return {"type": "score", "score": 2.0, "confidence": 0.9,
                    "probabilities": {"0": 1.0, "1": 0.0, "2": 0.0}}

        self.server.answer_fn = answer_fn
        out, saved = evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_budget_ms=20000, dockerfile_path=self.dockerfile_path,
        )
        self.assertGreater(len(self.server.requests), 0)  # Laya was actually consulted
        kept_lines = out.split("\n")[:-1]  # drop the trailing marker line
        expected_floor = lines[:evidence_reducer.HEAD_LINES] + lines[n_lines - evidence_reducer.TAIL_LINES:]
        self.assertEqual(set(kept_lines), set(expected_floor))
        # Every line here is distinct (indexed), so the set<->list line counts
        # matching too rules out a set() collapsing a duplicate-content bug.
        self.assertEqual(len(kept_lines), len(expected_floor))

    def test_critical_line_within_scanned_tail_window_is_kept(self):
        """T18 Checker finding (3c): a line classified "critical" (via
        probabilities, not score) is kept as long as it falls within the last
        LAYA_MAX_CALLS non-floor candidates (the tail-first scan window)."""
        n_lines = 200
        # Last candidate examined is TAIL_LINES back from the end; place the
        # critical line squarely inside the LAYA_MAX_CALLS-wide window that
        # follows it.
        critical_idx = n_lines - evidence_reducer.TAIL_LINES - evidence_reducer.LAYA_MAX_CALLS // 2
        lines = ["line %d: routine noise" % i for i in range(n_lines)]
        lines[critical_idx] = "line %d: the critical line" % critical_idx
        text = "\n".join(lines)

        def answer_fn(qid, q, req):
            line = req.get("state", {}).get(questions.REDUCER_STATE_KEY, "")
            if "the critical line" in line:
                return {"type": "score", "score": 1.0, "confidence": 0.9,
                        "probabilities": {"0": 0.0, "1": 0.0, "2": 1.0}}
            return {"type": "score", "score": 0.0, "confidence": 0.9,
                    "probabilities": {"0": 1.0, "1": 0.0, "2": 0.0}}

        self.server.answer_fn = answer_fn
        out, saved = evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_budget_ms=20000, dockerfile_path=self.dockerfile_path,
        )
        self.assertIn("the critical line", out)

    def test_critical_line_outside_scanned_tail_window_is_not_kept(self):
        """T18 Checker finding (3c), the cap's documented other side: a line
        classified "critical" is NOT kept if it falls outside the last
        LAYA_MAX_CALLS non-floor candidates -- this is the specified behavior of
        the call-count cap, not a bug: `_rank_candidates` never even sends that
        line to Laya, since LAYA_MAX_CALLS calls are already exhausted by the
        time the tail-first scan reaches it."""
        n_lines = 200
        # Comfortably beyond the LAYA_MAX_CALLS-wide window closest to the tail
        # (near the HEAD_LINES floor instead) -- must not be reached at all.
        far_idx = evidence_reducer.HEAD_LINES + 2
        lines = ["line %d: routine noise" % i for i in range(n_lines)]
        lines[far_idx] = "line %d: the critical line" % far_idx
        text = "\n".join(lines)

        def answer_fn(qid, q, req):
            line = req.get("state", {}).get(questions.REDUCER_STATE_KEY, "")
            if "the critical line" in line:
                return {"type": "score", "score": 1.0, "confidence": 0.9,
                        "probabilities": {"0": 0.0, "1": 0.0, "2": 1.0}}
            return {"type": "score", "score": 0.0, "confidence": 0.9,
                    "probabilities": {"0": 1.0, "1": 0.0, "2": 0.0}}

        self.server.answer_fn = answer_fn
        out, saved = evidence_reducer.reduce_text(
            text, session_id="s1", stream_name="stdout",
            calibration_file=self.calib_enabled, save_dir=self.tmpdir,
            endpoint=self.server.url, laya_budget_ms=20000, dockerfile_path=self.dockerfile_path,
        )
        self.assertNotIn("the critical line", out)


class TestFailOpenAtHookLevel(unittest.TestCase):
    def setUp(self):
        # evidence_reducer.py's own default save_dir (_save_full_text) resolves
        # `~/.claude/session-data/evidence-reducer/<session_id>` via
        # os.path.expanduser("~"), which reads HOME. main() (invoked as a real
        # subprocess here, exactly as the shim invokes it) never gets an
        # explicit save_dir, so without this override the two "large output"
        # tests below would actually write files under the REAL developer
        # $HOME every time this suite runs. Point HOME at a throwaway tempdir
        # instead so no test run ever touches the real home directory.
        self.fake_home = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.fake_home, ignore_errors=True)

    def _run_main(self, payload):
        proc = subprocess.run(
            [sys.executable, os.path.join(TEST_DIR, "evidence_reducer.py")],
            input=json.dumps(payload), capture_output=True, text=True, timeout=15,
            env={**os.environ, "HOME": self.fake_home},
        )
        return proc

    def test_short_output_reports_unchanged(self):
        proc = self._run_main({
            "session_id": "s1",
            "tool_response": {"stdout": "hi\n", "stderr": "", "interrupted": False, "isImage": False},
        })
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout.strip())
        self.assertFalse(out["changed"])

    def test_malformed_stdin_reports_unchanged_not_a_crash(self):
        proc = subprocess.run(
            [sys.executable, os.path.join(TEST_DIR, "evidence_reducer.py")],
            input="not valid json{{{", capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout.strip())
        self.assertFalse(out["changed"])

    def test_large_output_reports_changed_and_preserves_shape(self):
        text = _make_log(300, critical_at={5, 250})
        proc = self._run_main({
            "session_id": "s1",
            "tool_response": {"stdout": text, "stderr": "", "interrupted": False, "isImage": False},
        })
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout.strip())
        self.assertTrue(out["changed"])
        tr = out["tool_response"]
        self.assertIn("stdout", tr)
        self.assertEqual(tr["interrupted"], False)
        self.assertEqual(tr["isImage"], False)
        self.assertIn("FATAL ERROR", tr["stdout"])

    def test_large_stdout_and_stderr_together_stay_under_hook_timeout(self):
        """End-to-end worst-case latency check through main() itself (real
        committed calibration/dockerfile, reducer_rank enabled, no mock server --
        this measures against whatever TYPESAFE_API_URL resolves to, which by
        default is the unset/remote-disallowed path, i.e. every Laya call fails
        fast) -- both streams combined must finish well under the hook's own
        external timeout (5s)."""
        text_a = _make_log(300, critical_at={5})
        text_b = _make_log(300, critical_at={5})
        start = time.monotonic()
        proc = self._run_main({
            "session_id": "s1",
            "tool_response": {"stdout": text_a, "stderr": text_b, "interrupted": False, "isImage": False},
        })
        elapsed = time.monotonic() - start
        self.assertEqual(proc.returncode, 0)
        self.assertLess(elapsed, 5.0)

    def test_main_shares_call_budget_across_stdout_and_stderr(self):
        """T18 Checker finding (trial 2): pins that `main()` itself actually wires
        ONE shared `_CallBudget` into BOTH its stdout and stderr `reduce_text()`
        calls -- not merely that `reduce_text()`/`_rank_candidates` support a
        shared budget when a caller explicitly passes one in (which
        TestReducerRankFillsRemainingBudget's
        `test_shared_calls_budget_across_two_reduce_text_calls_caps_total_calls`
        already pins, at the `reduce_text()` level). Removing
        `calls_budget=shared_calls_budget` from either call inside `main()`
        would still pass every other test in this suite, yet let one hook
        invocation issue up to 2*LAYA_MAX_CALLS calls total (one full
        LAYA_MAX_CALLS budget per stream) instead of LAYA_MAX_CALLS.

        Runs the real subprocess entrypoint (same `_run_main` pattern as the
        other tests here) with both stdout and stderr large enough to have far
        more non-floor candidates than LAYA_MAX_CALLS each, and redirects Laya
        calls to a local MockLayaServer via `TYPESAFE_API_URL` (loopback, so no
        TYPESAFE_API_KEY is needed -- see jev_client.py's `_endpoint_loopback_status`).
        Uses the real committed calibration/Dockerfile (unchanged from
        TestRealCommittedCalibrationIsANoOp's own reliance on the same fact):
        reducer_rank is enabled there, so `main()` actually attempts ranking on
        both streams rather than short-circuiting as a no-op."""
        server = MockLayaServer()
        try:
            text_a = _make_log(300)
            text_b = _make_log(300)
            proc = subprocess.run(
                [sys.executable, os.path.join(TEST_DIR, "evidence_reducer.py")],
                input=json.dumps({
                    "session_id": "s1",
                    "tool_response": {
                        "stdout": text_a, "stderr": text_b,
                        "interrupted": False, "isImage": False,
                    },
                }),
                capture_output=True, text=True, timeout=15,
                env={**os.environ, "HOME": self.fake_home, "TYPESAFE_API_URL": server.url},
            )
            self.assertEqual(proc.returncode, 0)
            self.assertLessEqual(len(server.requests), evidence_reducer.LAYA_MAX_CALLS)
        finally:
            server.shutdown()


if __name__ == "__main__":
    unittest.main()
