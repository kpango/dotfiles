#!/usr/bin/env python3
"""guard_advisor -- System-1 (Laya) post-stage advisory layer for decide.py's
`security_shell` family (CONTEXT.md "ai-env-deepresearch-overhaul",
I-2/I-3/I-10/I-13/I-14).

Called by decide.py AFTER the deterministic shell_command_rules decision is already
computed -- never before it, and never in place of it (I-10: the deterministic tool
remains the first authority; this module only ever adjusts what it is handed).

Contract (`apply()`):
  apply(decision, reason, command, *, harness=None, calibration_file=None,
        timeout=None, endpoint=None, dockerfile_path=None)
      -> (decision, reason, laya_info | None)

  - decision/return value use decide.py's own three-value vocabulary
    ("allow"/"ask"/"block" -- NOT Claude's "allow"/"ask"/"deny" permissionDecision
    strings; the calling shim already maps this the same way it maps every other
    handle_security_shell() output).
  - `harness` must be one of "claude"/"agy"/"pi" (I-14: "各 shim は decide.py への
    入力で harness を明示的に渡す。harness が無ければ System-1 の後段は適用しない").
    Any other value (None, missing, unknown string) is a no-op with NO Laya call,
    exactly like a deterministic "block" below -- this is the cross-harness
    opt-in gate, checked before anything else.
  - `decision == "block"` is returned completely unchanged, with NO Laya call at
    all (I-2 hard floor: no permission can relax a deterministic block, so there
    is nothing left to compute).
  - If no guard_* capability is `"enabled": true` (after both the I-13 revision
    gate in `revision_check.load_verified_calibration()` AND, when
    `harness == "agy"`, forcing `guard_relax` off -- see below), returns
    (decision, reason, None) unchanged, again with NO Laya call -- zero added
    latency when every guard capability is disabled, which is the case for all
    of guard_strengthen/guard_deny/guard_relax as of laya-calibration.json
    committed by T17 (2026-09-24).
  - I-14 (agy): agy's shim has no intermediate "ask"/confirm primitive and maps
    both decide.py's "ask" and "block" to its own single "deny" -- relaxing an
    "ask" straight to "allow" would, from agy's perspective, turn what it treats
    as a hard deny into an outright allow in one step. The human decision
    (CONTEXT.md I-14) is that `guard_relax` is therefore ALWAYS disabled when
    `harness == "agy"`, regardless of what the calibration file itself declares
    -- `guard_strengthen` is unaffected (agy already denies an "ask", so
    strengthening one to a "block" changes nothing observable for agy; it is
    still evaluated and applied normally).
  - On ANY other failure (calibration file missing/malformed, revision mismatch,
    jev_client.evaluate() returning None for any reason at all -- disabled, no
    key, timeout, HTTP error, malformed response, disallowed endpoint), returns
    (decision, reason, None) unchanged (I-3 fail-to-deterministic).
  - Never constructs its own endpoint URL: `endpoint`/`timeout` are passed
    straight through to `jev_client.evaluate()`, which alone decides the target
    via its own TYPESAFE_API_URL-env-var-then-default chain and validates it
    against its own loopback/https allow-list (I-6, redefined). `endpoint`/
    `timeout` exist on this function only so tests can point at a mock server;
    decide.py's own call site never passes them.
"""
from __future__ import annotations

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import jev_client  # noqa: E402
import questions  # noqa: E402
import revision_check  # noqa: E402

DEFAULT_CALIBRATION_FILE = revision_check.DEFAULT_CALIBRATION_FILE

_KNOWN_HARNESSES = ("claude", "agy", "pi")

# Checked in this order: guard_deny is the strictest-bar capability (I-13: zero safe
# false positives required to enable) and is allowed to escalate straight to "block"
# from either "allow" or "ask" -- deliberately not restricted to originate from
# "allow" only, since the task's own spec lists it as a bare "-> deny" transition,
# unlike guard_strengthen ("allow -> ask") and guard_relax ("ask -> allow"), which
# both name their origin state explicitly.
_GUARD_CAPABILITIES = ("guard_strengthen", "guard_deny", "guard_relax")


def _enabled_capabilities(calibration: dict, harness: str) -> dict:
    """Return {name: threshold} for every guard_* capability whose own "enabled" is
    literally `True` (not a truthy string) and whose "threshold" is a real,
    non-bool number, in `calibration` (already revision-gated by the caller).
    Anything else (missing entry, "enabled": "true", missing/non-numeric
    threshold) is treated as disabled: a malformed capabilities entry must never
    silently *enable* a permission (fail closed for enabling). When
    `harness == "agy"`, `guard_relax` is dropped unconditionally (I-14)."""
    out = {}
    caps = calibration.get("capabilities", {})
    for name in _GUARD_CAPABILITIES:
        if harness == "agy" and name == "guard_relax":
            continue
        entry = caps.get(name)
        if not isinstance(entry, dict):
            continue
        if entry.get("enabled") is not True:
            continue
        threshold = entry.get("threshold")
        if not isinstance(threshold, (int, float)) or isinstance(threshold, bool):
            continue
        out[name] = threshold
    return out


def apply(
    decision,
    reason,
    command,
    *,
    harness=None,
    calibration_file=None,
    timeout=None,
    endpoint=None,
    dockerfile_path=None,
):
    if harness not in _KNOWN_HARNESSES:
        return decision, reason, None
    if decision == "block":
        return decision, reason, None

    # Defense in depth (Checker-reported defect, revision 2 review): everything
    # below this point does I/O (calibration file, Dockerfile cross-check via
    # revision_check, an HTTP call via jev_client) and this function's own
    # docstring already promises "on ANY other failure ... returns (decision,
    # reason, None) unchanged (I-3 fail-to-deterministic)". revision_check.py
    # now catches its own read/parse exceptions internally, but this try/except
    # makes that promise hold even if a future change to revision_check/
    # jev_client/questions reintroduces an uncaught exception somewhere in this
    # chain -- an uncaught exception here previously propagated all the way out
    # of decide.py (crashing it, empty stdout, nonzero exit), and every one of
    # the three shims' own "decide.py itself is unreachable" fallback then
    # returned a blanket ALLOW, silently downgrading a deterministic "ask" to
    # "allow". decide.py's own call site also wraps this call for the same
    # reason (belt and suspenders at a security-critical boundary).
    try:
        calibration = revision_check.load_verified_calibration(
            calibration_file=calibration_file, dockerfile_path=dockerfile_path
        )
        if calibration is None:
            return decision, reason, None

        enabled = _enabled_capabilities(calibration, harness)
        if not enabled:
            return decision, reason, None

        result = jev_client.evaluate(
            questions.guard_state(command),
            questions.GUARD_QUESTIONS,
            timeout=timeout,
            endpoint=endpoint,
        )
        if result is None:
            return decision, reason, None

        answer = result.get(questions.GUARD_QUESTION_ID)
        if not isinstance(answer, dict):
            return decision, reason, None
        probability = answer.get("noul")
        if not isinstance(probability, (int, float)) or isinstance(probability, bool):
            return decision, reason, None

        new_decision = decision
        new_reason = reason
        applied_capability = None

        if "guard_deny" in enabled and probability >= enabled["guard_deny"]:
            new_decision = "block"
            applied_capability = "guard_deny"
        elif decision == "allow" and "guard_strengthen" in enabled and probability >= enabled["guard_strengthen"]:
            new_decision = "ask"
            applied_capability = "guard_strengthen"
        elif decision == "ask" and "guard_relax" in enabled and probability < enabled["guard_relax"]:
            new_decision = "allow"
            applied_capability = "guard_relax"

        if applied_capability is not None:
            suffix = "[laya %s p=%.4f]" % (applied_capability, probability)
            new_reason = ("%s %s" % (reason, suffix)).strip() if reason else suffix

        laya_info = {
            "probability": probability,
            "enabled_capabilities": sorted(enabled),
            "applied_capability": applied_capability,
            "decision": new_decision,
        }
        return new_decision, new_reason, laya_info
    except Exception:
        return decision, reason, None
