#!/usr/bin/env python3
"""Shared System-1 (Laya/Jev) question definitions and the deterministic critical-line
regex, for the three coding-domain capabilities calibrated in
`agent/scripts/jev/calibration/calibrate.py` (CONTEXT.md, "ai-env-deepresearch-overhaul",
Addendum I-13):

  - guard_strengthen / guard_deny / guard_relax: is a shell command dangerous?
  - tier_raise: how complex is a described software task (swarm-implement's
    trivial/simple/standard/complex complexity gate)?
  - reducer_rank: how important is one build/test log line (noise/context/critical)?

Stdlib only -- this module is imported both by `calibrate.py` (which also imports
`laya`, torch, etc.) and, later, by the production hook path (`decide.py` / the
Claude evidence-reducer hook / the swarm-implement tier advisor), which must NOT pick
up a `laya`/`torch` dependency just to read these constants. The wire format
(`{"type": "noul"|"choice"|"score", "instructions": str, "criteria": ...}`) matches
both `laya.Agent.system_one()`'s question shape and the Jev `POST /v1/systemone`
wire protocol `agent/scripts/jev/jev_client.py` speaks, so the same dict can be
handed to either backend unchanged.

Each state dict below uses exactly one key, named for what it holds -- this is the
state shape `calibrate.py` sends per example, and what the production hook must
match when it builds a state for the same question.
"""
import re

# ---------------------------------------------------------------------------
# guard: is a shell command dangerous? (noul: P(dangerous)=1.0 in state["command"])
# ---------------------------------------------------------------------------

GUARD_STATE_KEY = "command"
GUARD_QUESTION_ID = "dangerous"

GUARD_QUESTIONS = {
    GUARD_QUESTION_ID: {
        "type": "noul",
        "instructions": (
            "Would running `command` on this machine, exactly as shown and without "
            "further confirmation, risk unintended or irreversible damage -- destroying "
            "or overwriting files, discarding version-control history, granting "
            "unintended access or privilege, exfiltrating credentials or secrets, "
            "executing unreviewed remote code, or altering production infrastructure, "
            "databases, or running services?"
        ),
        "criteria": {
            "true": "the command is destructive, irreversible, or unauthorized in its effect",
            "false": "the command is routine, read-only, reversible, or scoped to local/dev artifacts",
        },
    }
}


def guard_state(command: str) -> dict:
    return {GUARD_STATE_KEY: command}


# ---------------------------------------------------------------------------
# tier: how complex is a described software task? (choice over the swarm-implement
# complexity gate's four tiers, ordered trivial -> complex so callers can compare by
# list index -- CONTEXT.md I-4/I-13 "tier_raise: 高い方を採用" needs that ordering.)
# ---------------------------------------------------------------------------

TIER_STATE_KEY = "description"
TIER_QUESTION_ID = "tier"

# Ordered trivial -> complex. Index in this list IS the tier's rank for "adopt the
# higher of two tiers" comparisons -- do not reorder without updating every caller
# that compares by index.
TIER_LEVELS = ["trivial", "simple", "standard", "complex"]

TIER_QUESTIONS = {
    TIER_QUESTION_ID: {
        "type": "choice",
        "instructions": (
            "How complex is implementing the software task described in `description`, "
            "under swarm-implement's complexity gate?"
        ),
        "criteria": {
            "trivial": "one file, at most 15 lines changed, no new logic (e.g. a typo fix, a constant rename)",
            "simple": "at most 30 lines changed in one function, following an existing pattern already used in the codebase",
            "standard": "touches multiple files, or introduces new logic/behavior",
            "complex": "spans multiple systems, requires a new abstraction, or needs algorithm/design work",
        },
    }
}


def tier_state(description: str) -> dict:
    return {TIER_STATE_KEY: description}


# ---------------------------------------------------------------------------
# reducer: how important is one build/test log line? (score over noise/context/
# critical, ordered least -> most important so the expected-value score in
# laya's `score` answer type is directly comparable to this list's index.)
# ---------------------------------------------------------------------------

REDUCER_STATE_KEY = "line"
REDUCER_QUESTION_ID = "importance"

REDUCER_LEVELS = ["noise", "context", "critical"]

REDUCER_QUESTIONS = {
    REDUCER_QUESTION_ID: {
        "type": "score",
        "instructions": (
            "How important is `line` -- one line from a build or test log -- to a "
            "developer diagnosing what happened?"
        ),
        "criteria": [
            "noise: routine progress or informational output with no diagnostic value, "
            "including a passing/successful final summary (e.g. 'PASS', '12 passed; 0 failed')",
            "context: relevant surrounding information (a test name, a step header, a "
            "stack-trace frame, a non-fatal warning) but not itself a failure signal",
            "critical: reports a failure, error, or panic, or a final summary that "
            "indicates failure -- not a summary that indicates success",
        ],
    }
}


def reducer_state(line: str) -> dict:
    return {REDUCER_STATE_KEY: line}


def reducer_predicted_class(probabilities):
    """Argmax over a REDUCER_QUESTIONS[...] answer's `probabilities` dict
    (stringified index -> probability, indices into REDUCER_LEVELS above) -- returns
    the predicted class label ("noise"/"context"/"critical").

    This is the EXACT rule `agent/scripts/jev/calibration/calibrate.py`'s own
    `calibrate_reducer.predict()` uses to decide whether Laya called a held-out line
    "critical" for its `held_out_laya_critical_recall` metric (T18 Checker finding:
    `evidence_reducer.py`'s production ranking previously used the raw `score` field
    and a fixed call-count cutoff instead, which does not match what was actually
    calibrated and effectively made the ranking a no-op). Centralizing the argmax
    here -- rather than duplicating it in both calibrate.py and evidence_reducer.py --
    means production selection and the held-out metric that justified enabling
    reducer_rank can never silently drift apart.

    Raises KeyError/TypeError on a malformed `probabilities` dict, same as the
    original inline calibrate.py code did -- calibrate.py's own design deliberately
    never silently degrades a calibration measurement (see its module docstring).
    Callers that need a fail-closed default on production's hot path (evidence_reducer.py)
    wrap this call in their own try/except, matching that module's existing
    "any failure omits this line" pattern.
    """
    best_idx = max(range(len(REDUCER_LEVELS)), key=lambda i: probabilities[str(i)])
    return REDUCER_LEVELS[best_idx]


# ---------------------------------------------------------------------------
# Deterministic critical-line extraction (the Reducer's fail-to-deterministic
# fallback, CONTEXT.md I-5, and the baseline `reducer_rank` is calibrated against).
# Stdlib-only, shared with the not-yet-written Claude evidence-reducer hook so both
# use the exact same definition of "critical".
#
# T17 attempt 5 -- spec correction, not a bug fix (the orchestrator's own prior
# instructions were wrong, per an independent Checker's attempt-4 review):
# DETERMINISTIC_CRITICAL_PATTERN is a **recall-first safety floor**, not a
# precision filter. In the Reducer's log-summarization use (T11), a line this
# pattern matches is always KEPT; missing a genuine failure line is a real
# correctness bug (the developer never sees it), while over-keeping a passing/
# routine line only costs a little compression -- an acceptable, bounded cost.
#
# T17 attempt 6 -- human-approved final correction, after a third independent
# Checker reproduced real failure lines *still* missed by attempt 5's pattern:
# "FATAL_ERROR: out of memory" and "...'std::runtime_error'" were missed because
# `\bfatal\b`/`\berror\b` require a non-word character immediately after the
# keyword, and `_` (as in "FATAL_ERROR", "runtime_error") is itself a word
# character, so no `\b` fires there; "build-failed" and "health-check-failed:
# ..." were missed because of the `(?<!-)` lookbehind meant only to exclude the
# CLI flag `--no-fail-fast`, which also (wrongly) excludes any real "...-failed"
# text. Attempt 5's own README already claimed "every exclusion that could hide
# a real failure line was removed" -- that claim was wrong; `\b` itself, and the
# `-` lookbehind, are exclusions of exactly that kind (see the corrected
# revision-3-continued section in README.md's attempt-5 write-up, marked
# "(corrected in attempt 6)").
#
# The human-decided fix (final): DETERMINISTIC_CRITICAL_PATTERN is now a plain,
# case-insensitive **substring** match over DETERMINISTIC_CRITICAL_KEYWORDS --
# no `\b`, no lookaround, no exclusion of any kind. A keyword's inflected forms
# (fail/fails/failed/failing/failure/failures, error/errors, panic/panicked/
# panicking, assert/assertion/asserted, ...Error/...Exception suffixes, Go's
# capitalized "FAIL") are all covered automatically by substring matching, so
# the attempt-3 pluralization alternatives and the attempt-3 CamelCase
# case-sensitivity branch are both now redundant and removed -- a plain
# case-insensitive "error" substring already matches "TypeError", "errors", and
# "ERROR" alike. This trades away essentially all precision (many lines that
# merely *contain* one of these stems -- "error_handling.go", "--no-fail-fast",
# "pkg/errors", a passing "TestParseError", a stack frame naming "panic.go" --
# will also match) for the simplest possible guarantee against a false negative:
# if a keyword stem appears anywhere in the line, in any case or surrounding
# context (multi-word stems with any run of spaces, tabs, underscores or
# hyphens, including none, between their words), it is kept. Accepted false positives from this design are
# pinned down (asserted `True`, not `False`) in
# `test_calibration.TestDeterministicCriticalPattern.ACCEPTED_FALSE_POSITIVES`,
# and `test_calibration.TestDeterministicPatternHasNoExclusions` mechanically
# checks the compiled pattern's source contains no `\b`, `(?<`, `(?!`, or `(?=`
# construct, so a future change cannot silently reintroduce one of the
# recall-harming exclusions removed across attempts 5 and 6.
#
# Deliberately NOT covered by this pattern -- these are false negatives that no
# keyword-substring approach can catch, since the line contains none of this
# pattern's keyword stems at all: see README.md's attempt-6 section for the full
# enumeration against the current loglines dataset (the only dataset this
# pattern is evaluated on).
# ---------------------------------------------------------------------------

# Keyword stems for the deterministic critical-line match -- matched as a plain,
# case-insensitive substring, deliberately with no word-boundary or exclusion
# logic (see the design notes above for why). Substring matching covers other
# word forms only where the entry is a true stem. Most entries are stems, e.g.
# "fail" (fails/failed/failing/failure), "error" (errors, ...Error), "panic"
# (panicked/panicking), "assert" (assertion/asserted), "deni"/"deny"
# (denied/denial/denies), "refus" (refused/refusing/refusal). The timeout
# family has no single common substring, so its forms are listed as separate
# entries ("time out"/"timed out"/"times out"/"timing out"). Every word form
# named in this comment is pinned by
# test_calibration.TestDeterministicCriticalPattern.CLAIMED_WORD_FORMS, which
# requires a POSITIVE_CASES line per form that only the claimed entry matches.
# Forms of words NOT in this list (e.g. "deadline exceeded") are out of scope
# by design.
DETERMINISTIC_CRITICAL_KEYWORDS = (
    "fail",
    "error",
    "fatal",
    "panic",
    "exception",
    "traceback",
    "segfault",
    "segmentation fault",
    "assert",
    "deni",
    "deny",
    "refus",
    "time out",
    "timed out",
    "times out",
    "timing out",
    "deadlock",
    "undefined",
)

# Multi-word stems join their words with `[\s_-]*` (zero or more spaces, tabs,
# underscores or hyphens), so "timeout", "TimedOut", "timed\tout", "TIMED_OUT",
# "timed-out" and "Segmentation  fault" all match. Attempt 6 joined them with
# exactly one literal space, a recall regression vs. attempt 5. `[\s_-]*` only
# widens a match; it is not a boundary or exclusion construct.
DETERMINISTIC_CRITICAL_PATTERN = re.compile(
    "|".join(
        r"[\s_-]*".join(re.escape(word) for word in keyword.split())
        for keyword in DETERMINISTIC_CRITICAL_KEYWORDS
    ),
    re.IGNORECASE,
)


def is_deterministic_critical(line: str) -> bool:
    """True if `line` contains any of DETERMINISTIC_CRITICAL_KEYWORDS as a plain,
    case-insensitive substring -- the Reducer's fail-to-deterministic fallback and
    `reducer_rank`'s baseline. Recall-first by design (T17 attempts 5-6): a false
    positive (a noise/context line this also matches) is an accepted, bounded
    cost; a false negative (a real failure line this misses) is not -- so this
    deliberately has no word-boundary, lookaround, or exclusion logic of any kind.
    See the module-level design notes for the two attempts at adding exclusions
    that each ended up hiding a real failure line instead."""
    return bool(DETERMINISTIC_CRITICAL_PATTERN.search(line))
