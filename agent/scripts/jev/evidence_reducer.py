#!/usr/bin/env python3
"""evidence_reducer -- Claude-only PostToolUse(Bash) log-compression core
(CONTEXT.md "ai-env-deepresearch-overhaul" T11 / I-5). Called by the
agent/hooks/claude/evidence-reducer.sh shim, which is the only harness with a
`updatedToolOutput` PostToolUse primitive (CONTEXT.md 責務境界: "Reducer は Claude の
updatedToolOutput 前提のため Claude のみ").

Design (I-5, all bullet points are hard invariants, not tuning knobs):
  - Every line in the output is either (a) a line already present verbatim in the
    input, in its original relative order, or (b) the ONE synthetic marker line
    this module itself appends (`"[evidence-reducer: kept K of N lines; full
    output: PATH]"`), which is always last and is unambiguously distinguishable
    from a real log line by that bracketed prefix. No other generated text is
    ever mixed in, and (a)-lines are never reordered, paraphrased, or truncated.
  - Every line matching `questions.is_deterministic_critical()` is always kept
    (the recall-first safety floor T17 calibrated against), plus the
    CRITICAL_CONTEXT_LINES lines immediately following each one (T15 -- a
    critical line's own companion detail, e.g. Go's assertion-detail line or
    Rust's `-->` location line, often carries no keyword of its own), plus a
    fixed number of head/tail lines for orientation -- these three groups are
    the unconditional floor and are kept even if that means exceeding the
    nominal line budget below.
  - Only the *remaining* budget (if any) is filled by Laya's `reducer_rank`
    capability, when enabled (after the I-13 revision gate,
    `revision_check.load_verified_calibration()`): at most LAYA_MAX_CALLS
    non-floor candidate lines are sent to Laya, scanned TAIL-FIRST (a build/test
    failure summary tends to cluster near the end of a log, not the start -- see
    `reduce_text()`'s candidate-ordering comment), and only the ones Laya
    classifies "critical" are added -- via `questions.reducer_predicted_class()`'s
    argmax over the answer's `probabilities`, the EXACT rule `calibrate.py` used
    to measure this capability's held-out recall (T18 Checker finding: using the
    raw `score` value plus a fixed cutoff, as an earlier revision of this module
    did, does not match what was actually calibrated and makes the "ranking"
    step select an arbitrary fixed window rather than lines Laya actually judged
    important). Otherwise (disabled, revision unverified, Laya fails, or the
    call/time budget already exhausted by the floor) no extra lines are added --
    a smaller, deterministic-only output is an acceptable, bounded
    compression-quality cost, never a correctness violation, because the floor
    above never changes.
  - The full, unreduced text is saved to a session-scoped file (mode 0600) BEFORE
    any line is dropped. If that save fails for any reason, reduction is aborted
    and the original text is returned unchanged -- this module must never claim
    "full output: <path>" without that path actually existing and being readable
    only by the owner.
  - Any failure anywhere in this module (calibration file missing/malformed,
    jev_client.evaluate() returning None, an unexpected exception) degrades to
    "return the input unchanged" -- never raises out of `reduce_text()`.

Laya time budget is a single, SHARED wall-clock deadline across BOTH stdout and
stderr within one hook invocation (`main()` computes it once and passes the same
absolute deadline into both `reduce_text()` calls) -- not per-stream, which would
let a large stdout AND a large stderr each separately spend up to
LAYA_TOTAL_BUDGET_MS, doubling the worst case. See LAYA_TOTAL_BUDGET_MS's own
comment for the full worst-case latency arithmetic against the hook's own
external timeout (5s, both agent/hooks/claude/evidence-reducer.sh's internal
`timeout 5` and agent/harnesses/claude/settings.json's hook `"timeout": 5`).

The LAYA_MAX_CALLS call-COUNT budget is likewise a single, SHARED counter across
both `reduce_text()` calls (`main()` creates ONE `_CallBudget` and passes the same
object into both) -- NOT a per-`reduce_text()`-call local counter (T18 Checker
finding: an earlier revision reset the counter inside `_rank_candidates` on every
call, so one hook invocation could issue up to 2*LAYA_MAX_CALLS calls total, one
LAYA_MAX_CALLS budget per stream, instead of LAYA_MAX_CALLS total).
"""
from __future__ import annotations

import json
import os
import re
import stat
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import jev_client  # noqa: E402
import questions  # noqa: E402
import revision_check  # noqa: E402

DEFAULT_CALIBRATION_FILE = revision_check.DEFAULT_CALIBRATION_FILE

# Lower bound of the "対象帯" CONTEXT.md line 301-302 records (4KiB-30000 chars):
# below 4096 characters there are, in practice, few enough lines that compressing
# saves little and risks losing orientation for no real benefit. No upper bound is
# enforced here -- CONTEXT.md's same citation records that Claude Code's own native
# truncation (BASH_MAX_OUTPUT_LENGTH, default 30000) already caps what a
# PostToolUse hook ever receives for Bash, so nothing above that ever reaches this
# module in the first place.
REDUCER_MIN_CHARS = 4096

# Fixed, deliberately simple choices (Ponytail YAGNI: not derived from the
# calibration dataset, which only measures per-line critical/noise/context
# classification, not an optimal head/tail/budget split) -- tunable later if a
# human decides the compression ratio needs adjusting.
HEAD_LINES = 5
TAIL_LINES = 5
MAX_KEPT_LINES = 40

# T15: number of lines immediately following each deterministic-critical line
# (questions.is_deterministic_critical()) that are unconditionally kept too --
# widens the floor, never narrows it (existing floor members are unaffected).
# Value 2: a Go test failure splits its signal across two separate log lines
# ("--- FAIL: TestSearch (0.03s)" then, on the very next line, the assertion
# detail "    main_test.go:88: expected 3 results, got 2") and neither
# `is_deterministic_critical()`'s keyword list nor a keyword substring match
# fires on that second line at all -- without this, the assertion detail a
# developer actually needs was silently dropped whenever the budget ran out
# before reaching it. Rust's `error[E0382]: ...` diagnostic is likewise
# followed by a `-->` location line with no keyword of its own. 2 lines covers
# both single-companion-line shapes with a one-line margin for a diagnostic
# that spans one extra line (e.g. a blank separator before the arrow), without
# needing to special-case either language's exact log shape.
CRITICAL_CONTEXT_LINES = 2

# Wall-clock cap, SHARED across stdout+stderr in one hook invocation (see
# `main()`), on the *cumulative* time spent issuing per-line Laya `score()`
# calls. A large log can have far more remaining-budget candidate lines than
# fit in this window, so this bounds tail latency for the synchronous
# PostToolUse hook -- candidates not reached before the deadline are simply
# left unscored (degrades to a smaller kept-line set, never blocks
# indefinitely).
#
# 600ms (down from an earlier 2000ms -- perf-review finding, T18): reducer_rank
# is the one capability T17's calibration left enabled, and when the sidecar
# runs on CPU (measured p50 160ms/call, p95 180.7ms -- res-cpu-english.json's
# `guard.p50_ms`/`guard.p95_ms`, CONTEXT.md "ai-env-deepresearch-overhaul" 追補5),
# a 2000ms budget let this synchronous hook spend up to ~12 sequential calls
# (2000/160) and nearly exhaust the whole soft deadline on almost every
# large-log invocation. At 600ms, only ~3-4 calls (600/160) complete before the
# deadline in that CPU case, keeping this hook's own added latency small
# relative to the 5000ms external timeout below.
#
# Each call's OWN timeout is separately capped to whatever is left until this
# deadline (`_rank_candidates`'s `call_timeout = min(requested, remaining_ms)`
# -- see its own docstring for the defect this fixes, revision 2 review): a
# user-configured `JEV_TIMEOUT_MS` env var (or an explicit `timeout=` kwarg)
# larger than the remaining budget can therefore never let a single call run
# past this deadline by that entire configured amount.
#
# LAYA_MAX_CALLS (below) is a SEPARATE, device-independent ceiling on top of
# this wall-clock deadline: on the GPU sidecar (measured p50 18.2ms/call,
# res-cuda-english.json's `guard.p50_ms`), 600ms alone would let roughly 33
# calls (600/18) complete -- an unbounded-feeling number of synchronous
# round trips for one hook invocation, and one a pathological run of
# near-instant failures (e.g. connection refused) could approach even faster
# than that. Capping the call COUNT keeps a sane, hardware-independent bound
# regardless of how fast any given sidecar responds.
#
# Worst-case total latency arithmetic (updated for the 600ms budget + 8-call
# cap, PER HOOK INVOCATION -- i.e. across BOTH the stdout and stderr
# `reduce_text()` calls combined, via the shared `_CallBudget` (T18 fix: an
# earlier revision's call-count cap was local to each `_rank_candidates` call,
# so the true worst case was 2*LAYA_MAX_CALLS=16 calls, one full 8-call budget
# per stream, not 8 total); documented, not measured against a real sidecar
# under load -- see the mission draft's own "未解決事項" for that caveat):
#   600ms (this soft deadline -- no single call's OWN timeout can exceed
#          whatever remains of it, by the per-call cap above; also bounded to
#          at most LAYA_MAX_CALLS=8 calls TOTAL for the whole hook invocation,
#          regardless of how fast each returns)
# + ~100ms (line-splitting/regex-matching over <=30000 chars, disk save I/O,
#          and the last call's own connect/fail-fast overhead when it is
#          given only a few ms of remaining budget -- all cheap, bounded,
#          and independent of any user-configured JEV_TIMEOUT_MS) generously
#          rounded up
# = ~700ms total, comfortably under the hook's own external timeout (5000ms,
#   both evidence-reducer.sh's internal `timeout 5` and settings.json's hook
#   `"timeout": 5` for the PostToolUse:Bash entry) -- regardless of how large a
#   user sets JEV_TIMEOUT_MS.
LAYA_TOTAL_BUDGET_MS = 600

# Hard ceiling on the number of Laya calls issued per HOOK INVOCATION (i.e.
# SHARED across the stdout and stderr `reduce_text()` calls `main()` makes -- see
# _CallBudget below -- not a per-`reduce_text()`-call or per-stream budget),
# independent of LAYA_TOTAL_BUDGET_MS (see that constant's own comment for why a
# wall-clock deadline alone is not enough on a fast sidecar or under pathological
# fast-failure conditions). 8: MAX_KEPT_LINES (40) minus the typical floor
# (HEAD_LINES + TAIL_LINES = 10, plus however many CRITICAL_CONTEXT_LINES-widened
# critical lines) can still leave room for many more than 8 candidates on a large
# log; 8 keeps comfortably fewer round trips than that while still letting
# reducer_rank meaningfully influence which lines fill the remaining budget
# (never zero, since a disabled/no-op ranking pass would just fall back to the
# deterministic floor alone). The unconditional floor (deterministic-critical +
# head/tail, T15's CRITICAL_CONTEXT_LINES included) is entirely unaffected by
# this cap -- it is applied only to the *ranking* pass that fills remaining
# budget, same scope as LAYA_TOTAL_BUDGET_MS.
LAYA_MAX_CALLS = 8


class _CallBudget:
    """Mutable call-count budget, SHARED across the stdout and stderr
    `reduce_text()` calls within one hook invocation (T18 Checker finding: a plain
    module-level int or a local variable inside `_rank_candidates` cannot be
    decremented by one `reduce_text()` call and observed by the other -- `main()`
    creates exactly ONE instance and passes it to both calls, the same pattern
    already used for the shared `laya_deadline`). `reduce_text()` creates a fresh
    one (worth LAYA_MAX_CALLS) when the caller doesn't pass one, keeping the
    single-call API convenient for direct use and for tests, same convention as
    `laya_deadline`'s own default."""

    __slots__ = ("remaining",)

    def __init__(self, remaining=LAYA_MAX_CALLS):
        self.remaining = remaining


def _reducer_rank_enabled(calibration_file: str, dockerfile_path=None) -> bool:
    calibration = revision_check.load_verified_calibration(
        calibration_file=calibration_file, dockerfile_path=dockerfile_path
    )
    if calibration is None:
        return False
    entry = calibration.get("capabilities", {}).get("reducer_rank")
    return isinstance(entry, dict) and entry.get("enabled") is True


# T15 (Checker-reported path-traversal gap): `session_id` currently comes from a
# Tier-B shim's CLAUDE_SESSION_ID env var and, in the future, may come from hook
# JSON input (`.session_id`) -- neither is validated upstream. Used unsanitized
# below, it is joined directly into the default save_dir, so a value like
# "../../etc", an absolute-looking component, or an embedded NUL could place the
# saved file outside the intended evidence-reducer/ directory. Any character
# outside this allow-list, an empty/oversized value, or exactly "." or ".."
# (both otherwise match the allow-list but are special path components) all
# collapse the WHOLE value to "unknown" -- never partially strip/escape, since a
# value this malformed is not trustworthy input to begin with.
#
# Checker-reported (revision 3 review): `.match()` against a `$`-anchored
# pattern is NOT equivalent to a full-string match -- Python's `re` `$` also
# matches immediately before a single trailing "\n", so `.match()` let
# "abc\n" (and "..\n"/".\n") through as if they equalled "abc"/".."/".". Using
# `.fullmatch()` (which requires the ENTIRE string to match, trailing
# newline included) instead of `.match()` against a `$`-anchored pattern
# closes that gap -- confirmed by mutation testing (see the test file).
_SESSION_ID_ALLOWED = re.compile(r"[A-Za-z0-9._-]+")
_SESSION_ID_MAX_LEN = 128


def _sanitize_session_id(session_id) -> str:
    if (
        not isinstance(session_id, str)
        or not session_id
        or session_id in (".", "..")
        or len(session_id) > _SESSION_ID_MAX_LEN
        or not _SESSION_ID_ALLOWED.fullmatch(session_id)
    ):
        return "unknown"
    return session_id


def _save_full_text(text: str, session_id: str, stream_name: str, save_dir):
    save_dir = save_dir or os.path.join(
        os.path.expanduser("~"), ".claude", "session-data", "evidence-reducer", _sanitize_session_id(session_id)
    )
    try:
        os.makedirs(save_dir, mode=0o700, exist_ok=True)
        ts = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        path = os.path.join(save_dir, "%s-%d-%s.log" % (ts, os.getpid(), stream_name))
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        # Defense in depth: assert the mode really is owner-only even if the
        # process umask or an unusual filesystem altered what os.open() requested.
        mode = stat.S_IMODE(os.stat(path).st_mode)
        if mode != 0o600:
            os.chmod(path, 0o600)
        return path
    except Exception:
        return None


def _rank_candidates(lines, candidates, deadline, timeout, endpoint, calls_budget):
    """Classify each candidate line via Laya's reducer_rank question and return
    only the ones Laya calls "critical" -- via `questions.reducer_predicted_class()`'s
    argmax over the answer's `probabilities`, the SAME rule
    `agent/scripts/jev/calibration/calibrate.py` used to measure this capability's
    held-out recall (T18 Checker finding: an earlier revision kept raw `score`
    values and simply took the highest-scoring candidates within the remaining
    budget, regardless of whether Laya actually judged them "critical" -- combined
    with the LAYA_MAX_CALLS cap, that made this pass functionally equivalent to
    "keep the first candidates examined" regardless of score, since remaining
    budget (typically ~30) is normally larger than LAYA_MAX_CALLS (8) and so never
    actually filtered anything by score).

    `candidates` is iterated in the ORDER GIVEN (T18: `reduce_text()` passes it
    tail-first -- from the last non-floor line backward -- since a build/test
    failure summary tends to cluster near the end of a log; see that call site's
    own comment). Stops issuing new calls once `deadline` (an absolute
    `time.monotonic()` timestamp, possibly shared with a sibling stream's own
    scoring pass -- see module docstring) has passed, OR once `calls_budget` (a
    `_CallBudget`, SHARED across both the stdout and stderr `reduce_text()` calls
    within one hook invocation -- see that class's own docstring) is exhausted;
    whatever wasn't reached is simply omitted (never invented, never blocks past
    the deadline or the call-count cap).

    Each call's own timeout is capped to whatever is left until `deadline`
    (Checker-reported "軽微な点", revision 2 review): passing `timeout`
    (or, if that's None, jev_client's own `JEV_TIMEOUT_MS`-env-or-800ms-default
    resolution) straight through to every call meant a user who configured a
    large `JEV_TIMEOUT_MS` (or an explicit large `timeout` kwarg) could let a
    SINGLE in-flight call run past `deadline` by that entire configured amount,
    on top of the deadline itself -- e.g. `JEV_TIMEOUT_MS=10000` plus the
    600ms soft deadline could reach ~10s, well past the hook's own 5s external
    timeout. Capping each call's timeout to `min(requested, remaining-until-
    deadline)` means even the very first call in the loop can never be given
    more time than is left in the shared budget, so the worst case collapses
    back down to roughly `LAYA_TOTAL_BUDGET_MS` itself plus a small,
    non-network-scaling constant (line-splitting/regex/disk-save overhead),
    regardless of how large a user's own JEV_TIMEOUT_MS is configured."""
    critical = []
    for i in candidates:
        if calls_budget.remaining <= 0:
            break
        remaining_ms = (deadline - time.monotonic()) * 1000.0
        if remaining_ms <= 0:
            break
        requested_ms = timeout if timeout is not None else jev_client._int_env(
            "JEV_TIMEOUT_MS", jev_client.DEFAULT_TIMEOUT_MS
        )
        call_timeout = min(requested_ms, remaining_ms)
        calls_budget.remaining -= 1
        answer = jev_client.evaluate(
            questions.reducer_state(lines[i]),
            questions.REDUCER_QUESTIONS,
            timeout=call_timeout,
            endpoint=endpoint,
        )
        if answer is None:
            continue
        q = answer.get(questions.REDUCER_QUESTION_ID)
        if not isinstance(q, dict):
            continue
        try:
            predicted = questions.reducer_predicted_class(q.get("probabilities"))
        except Exception:
            continue
        if predicted != "critical":
            continue
        # `score` is kept only as a best-effort secondary tiebreaker, for the rare
        # case remaining_budget (in reduce_text()) truncates a set of critical
        # hits larger than what's left to fill -- criticality (above), not raw
        # score, is what selects a line at all.
        score_val = q.get("score")
        if not isinstance(score_val, (int, float)) or isinstance(score_val, bool):
            score_val = float("-inf")
        critical.append((score_val, i))
    # Highest score first among the critical hits; original index as a stable tiebreaker.
    critical.sort(key=lambda t: (-t[0], t[1]))
    return [i for _, i in critical]


def reduce_text(
    text,
    *,
    session_id,
    stream_name,
    calibration_file=None,
    laya_budget_ms=LAYA_TOTAL_BUDGET_MS,
    laya_deadline=None,
    calls_budget=None,
    save_dir=None,
    timeout=None,
    endpoint=None,
    dockerfile_path=None,
):
    """Returns (output_text, saved_path_or_None). `output_text is text` (the exact
    same object) whenever no reduction was applied, so callers can cheaply check
    `reduced is not text` instead of a string comparison.

    `laya_deadline`, if given, is an absolute `time.monotonic()` timestamp shared
    across multiple `reduce_text()` calls (this is how `main()` enforces ONE
    combined TIME budget across stdout+stderr rather than one each). If omitted, a
    fresh deadline is computed from `laya_budget_ms` for this call alone (keeps
    the single-call API convenient for direct use and for tests).

    `calls_budget`, if given, is a `_CallBudget` shared the same way (this is how
    `main()` enforces ONE combined CALL-COUNT budget across stdout+stderr --
    T18 Checker finding: an earlier revision let each `reduce_text()` call spend
    up to LAYA_MAX_CALLS independently, so one hook invocation could issue up to
    2*LAYA_MAX_CALLS calls total). If omitted, a fresh `_CallBudget` (worth
    LAYA_MAX_CALLS) is created for this call alone, same convenience convention
    as `laya_deadline`."""
    try:
        if not isinstance(text, str) or len(text) < REDUCER_MIN_CHARS:
            return text, None

        lines = text.split("\n")
        n = len(lines)
        if n <= MAX_KEPT_LINES:
            return text, None  # already few enough lines; nothing to gain

        calibration_file = calibration_file or DEFAULT_CALIBRATION_FILE

        head_idx = set(range(min(HEAD_LINES, n)))
        tail_idx = set(range(max(0, n - TAIL_LINES), n))
        critical_idx = {i for i, line in enumerate(lines) if questions.is_deterministic_critical(line)}
        # T15: also keep the CRITICAL_CONTEXT_LINES lines right after each
        # critical line (see that constant's comment) -- widens the floor only,
        # so every index already in critical_idx/head_idx/tail_idx stays kept.
        for i in list(critical_idx):
            for j in range(i + 1, min(i + 1 + CRITICAL_CONTEXT_LINES, n)):
                critical_idx.add(j)
        kept_idx = head_idx | tail_idx | critical_idx

        if len(kept_idx) < MAX_KEPT_LINES and _reducer_rank_enabled(calibration_file, dockerfile_path=dockerfile_path):
            remaining_budget = MAX_KEPT_LINES - len(kept_idx)
            # T18 Checker finding: scan tail-first (last line back to first), not
            # in ascending original order. A build/test failure summary tends to
            # cluster near the END of a log (the tool's own final report), and
            # LAYA_MAX_CALLS bounds how many candidates ever get examined at all --
            # scanning ascending meant the examined window was always "the first
            # LAYA_MAX_CALLS non-floor lines", which has no particular reason to
            # contain the summary. This is a heuristic ordering choice (not
            # calibrated), not a correctness invariant.
            candidates = [i for i in range(n - 1, -1, -1) if i not in kept_idx]
            if candidates:
                deadline = laya_deadline if laya_deadline is not None else time.monotonic() + laya_budget_ms / 1000.0
                budget = calls_budget if calls_budget is not None else _CallBudget()
                ranked = _rank_candidates(lines, candidates, deadline, timeout, endpoint, budget)
                for i in ranked[:remaining_budget]:
                    kept_idx.add(i)

        if len(kept_idx) >= n:
            return text, None  # the floor + ranking ended up covering every line

        # Full text must be safely on disk BEFORE we drop a single line -- if the
        # save fails, we do not reduce (never reference a path that doesn't exist).
        saved_path = _save_full_text(text, session_id, stream_name, save_dir)
        if saved_path is None:
            return text, None

        kept_sorted = sorted(kept_idx)
        out_lines = [lines[i] for i in kept_sorted]
        out_lines.append(
            "[evidence-reducer: kept %d of %d lines; full output: %s]" % (len(kept_sorted), n, saved_path)
        )
        return "\n".join(out_lines), saved_path
    except Exception:
        return text, None


def main(argv=None) -> int:
    """CLI used by agent/hooks/claude/evidence-reducer.sh. Reads one JSON object
    from stdin: {"session_id": str, "tool_response": {"stdout": str, "stderr": str,
    "interrupted": bool, "isImage": bool}} (Bash's own tool_response shape,
    CONTEXT.md line 300). Writes one JSON line to stdout:
      {"changed": false}                                    -- nothing to change
      {"changed": true, "tool_response": {...same shape...}} -- stdout/stderr
                                                                 replaced in place

    Always exits 0 -- the calling shim treats any non-zero exit, and any output
    that isn't valid `{"changed": ...}` JSON, as "leave the tool output alone"
    (fail-open at the shim layer, on top of this function's own internal
    try/except).

    Computes ONE shared Laya deadline (`LAYA_TOTAL_BUDGET_MS` from *now*) AND ONE
    shared call-count budget (`_CallBudget(LAYA_MAX_CALLS)`), and passes both to
    the stdout and stderr `reduce_text()` calls, so the two streams' combined Laya
    scoring time is capped at `LAYA_TOTAL_BUDGET_MS` total and their combined call
    count is capped at `LAYA_MAX_CALLS` total -- neither doubled (see module
    docstring)."""
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except Exception:
        print(json.dumps({"changed": False}))
        return 0
    if not isinstance(req, dict):
        print(json.dumps({"changed": False}))
        return 0

    session_id = req.get("session_id") or "unknown"
    tool_response = req.get("tool_response")
    if not isinstance(tool_response, dict):
        print(json.dumps({"changed": False}))
        return 0

    out = dict(tool_response)
    changed = False
    shared_deadline = time.monotonic() + LAYA_TOTAL_BUDGET_MS / 1000.0
    shared_calls_budget = _CallBudget()
    try:
        for stream_name in ("stdout", "stderr"):
            original = tool_response.get(stream_name)
            if not isinstance(original, str):
                continue
            reduced, _ = reduce_text(
                original, session_id=session_id, stream_name=stream_name,
                laya_deadline=shared_deadline, calls_budget=shared_calls_budget,
            )
            if reduced is not original:
                out[stream_name] = reduced
                changed = True
    except Exception:
        print(json.dumps({"changed": False}))
        return 0

    if not changed:
        print(json.dumps({"changed": False}))
        return 0
    print(json.dumps({"changed": True, "tool_response": out}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
