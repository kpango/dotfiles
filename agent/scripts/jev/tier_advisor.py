#!/usr/bin/env python3
"""tier_advisor -- CLI advisor for swarm-implement's complexity gate
(agent/skills/swarm-implement/SKILL.md "複雑度ガード"). Adopts the HIGHER of the
orchestrator's own deterministic tier judgment and Laya's `tier_raise` choice
(CONTEXT.md I-4/I-13) -- never lowers, and is a pure no-op (no Laya call) when
`tier_raise` is disabled, which is its state in laya-calibration.json as committed
by T17 (2026-09-24; held-out accuracy 0.535 < the 0.70 bar), and also a no-op
whenever the I-13 revision gate (`revision_check.load_verified_calibration()`)
cannot verify the calibration's recorded revision against
`dockers/laya.Dockerfile`'s pinned build-arg.

Contract:
  python3 tier_advisor.py --deterministic-tier <trivial|simple|standard|complex> \
      --description "<task description text>" \
      [--calibration-file PATH] [--timeout-ms N] [--endpoint URL]
      [--dockerfile-path PATH]

  Exit code: ALWAYS 0 for a usage-valid invocation -- this is advisory-only and must
  never block the orchestrator's own flow with a nonzero exit. The only nonzero
  exits are argparse's own usage-error exits (missing/invalid
  --deterministic-tier), which is the ordinary CLI contract for a bad invocation
  and is deliberately left untouched (same convention jev_client.py's own CLI
  uses for its own argparse errors).

  stdout: exactly one line of JSON:
    {"tier": <str>, "source": "deterministic"|"laya", "raised": bool,
     "deterministic_tier": <str>, "laya_tier": <str|null>,
     "laya_confidence": <float|null>}

  - "tier" is always >= "deterministic_tier" in TIER_LEVELS order -- never lower.
  - "source" is "laya" only when tier_raise is enabled AND Laya's own choice
    actually ranks strictly higher than the deterministic tier; otherwise
    "deterministic" (covers: tier_raise disabled, revision unverified, Laya call
    failed, Laya agreed, or Laya ranked the task *lower* -- Fable/Max
    budget-guard spot-review is never bypassed by this advisor per I-4, only
    ever added to).
"""
from __future__ import annotations

import argparse
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import jev_client  # noqa: E402
import questions  # noqa: E402
import revision_check  # noqa: E402

DEFAULT_CALIBRATION_FILE = revision_check.DEFAULT_CALIBRATION_FILE


def _deterministic_result(tier):
    """The no-op/fallback result shape: always exit-0-safe, never raises the
    tier above `tier` itself. Shared by advise()'s initial result, its own
    defense-in-depth except-handler, and main()'s outer except-handler (three
    call sites that previously duplicated this same dict literal)."""
    return {
        "tier": tier,
        "source": "deterministic",
        "raised": False,
        "deterministic_tier": tier,
        "laya_tier": None,
        "laya_confidence": None,
    }


def _tier_raise_enabled(calibration_file: str, dockerfile_path=None) -> bool:
    calibration = revision_check.load_verified_calibration(
        calibration_file=calibration_file, dockerfile_path=dockerfile_path
    )
    if calibration is None:
        return False
    entry = calibration.get("capabilities", {}).get("tier_raise")
    # Same fail-closed-for-enabling rule as guard_advisor._enabled_capabilities:
    # only a literal `True` counts.
    return isinstance(entry, dict) and entry.get("enabled") is True


def advise(
    deterministic_tier,
    description,
    *,
    calibration_file=None,
    timeout=None,
    endpoint=None,
    dockerfile_path=None,
):
    calibration_file = calibration_file or DEFAULT_CALIBRATION_FILE
    result = _deterministic_result(deterministic_tier)
    if deterministic_tier not in questions.TIER_LEVELS:
        return result

    # Defense in depth (Checker-reported defect, revision 2 review, same class
    # of bug as guard_advisor.apply()'s own try/except): everything below does
    # I/O (calibration file, Dockerfile cross-check via revision_check, an HTTP
    # call via jev_client). `revision_check.load_verified_calibration()` now
    # catches its own read/parse exceptions internally, but this try/except
    # makes `advise()`'s own documented "no-op on any failure" contract hold
    # even if something in this chain raises unexpectedly -- an uncaught
    # exception here previously propagated out of `main()` uncaught, breaking
    # this CLI's own "ALWAYS exit 0" contract (traceback on stderr, exit 1).
    try:
        if not _tier_raise_enabled(calibration_file, dockerfile_path=dockerfile_path):
            return result

        answer = jev_client.evaluate(
            questions.tier_state(description),
            questions.TIER_QUESTIONS,
            timeout=timeout,
            endpoint=endpoint,
        )
        if answer is None:
            return result
        q = answer.get(questions.TIER_QUESTION_ID)
        if not isinstance(q, dict):
            return result
        laya_tier = q.get("choice")
        if laya_tier not in questions.TIER_LEVELS:
            return result

        result["laya_tier"] = laya_tier
        result["laya_confidence"] = q.get("confidence")

        det_idx = questions.TIER_LEVELS.index(deterministic_tier)
        laya_idx = questions.TIER_LEVELS.index(laya_tier)
        if laya_idx > det_idx:
            result["tier"] = laya_tier
            result["source"] = "laya"
            result["raised"] = True
        return result
    except Exception:
        return _deterministic_result(deterministic_tier)


def main(argv=None) -> int:
    # argparse.parse_args() calls sys.exit() (raising SystemExit) on bad/missing
    # arguments -- that's the standard CLI contract for a usage error and must
    # pass through untouched, so it is deliberately outside the try/except below
    # (same convention jev_client.py's own CLI uses).
    parser = argparse.ArgumentParser(prog="tier_advisor")
    parser.add_argument("--deterministic-tier", required=True, choices=questions.TIER_LEVELS)
    parser.add_argument("--description", required=True)
    parser.add_argument("--calibration-file", default=None)
    parser.add_argument("--timeout-ms", type=int, default=None)
    parser.add_argument("--endpoint", default=None)
    parser.add_argument("--dockerfile-path", default=None)
    args = parser.parse_args(argv)

    # Defense in depth on top of advise()'s own try/except (Checker-reported
    # defect, revision 2 review): this CLI's own documented contract is
    # "ALWAYS exit 0 for a usage-valid invocation" -- an uncaught exception
    # anywhere in advise() previously broke that contract (traceback on
    # stderr, exit 1), which would have looked to a caller exactly like
    # decide.py's own crash-then-fallback-to-allow bug (this script has no
    # such fallback consumer today, but the "always exit 0" contract exists
    # specifically so callers can rely on that).
    try:
        result = advise(
            args.deterministic_tier,
            args.description,
            calibration_file=args.calibration_file,
            timeout=args.timeout_ms,
            endpoint=args.endpoint,
            dockerfile_path=args.dockerfile_path,
        )
    except Exception:
        result = _deterministic_result(args.deterministic_tier)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
