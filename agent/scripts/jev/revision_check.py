#!/usr/bin/env python3
"""revision_check -- shared I-13 revision gate for guard_advisor / tier_advisor /
evidence_reducer (CONTEXT.md "ai-env-deepresearch-overhaul", Addendum I-13: "ファイル
が無い、または revision が一致しない場合は、全権限を縮小側で動かす").

All three consumers must apply the SAME gate before trusting any capability's
"enabled" flag in laya-calibration.json, so it lives here once (Ponytail step 2:
Codebase Reuse) rather than being re-checked three times with room to drift.

Revision verification -- method and its documented limitation:
  laya 0.3.11's `laya-serve` `GET /health` endpoint returns only
  `{"status", "loaded", "device"}` (verified directly against the installed
  laya==0.3.11 package's own laya/serve.py source, 2026-09-24: the `health()`
  handler builds exactly that dict and nothing else; `Router.loaded` -- the one
  other thing `/health` exposes -- is a `List[str]` of loaded checkpoint *names*
  like "english", never a revision/commit hash). There is presently no live
  endpoint this module could query to confirm which commit a *running* sidecar
  was actually built from.

  The only available cross-check is therefore against `dockers/laya.Dockerfile`'s
  pinned `LAYA_HF_REVISION` build-arg, reusing
  `calibrate.check_dockerfile_revision()` (agent/scripts/jev/calibration/calibrate.py)
  rather than reimplementing the same regex -- that function (and
  `read_dockerfile_pinned_revision()` it calls) has no top-level laya/torch import
  (both are deferred into `calibrate.main()`'s own model-loading step), so
  `import calibrate` here does not add a laya/torch dependency to the production
  hook path; `test_revision_check.py` pins this with its own regression test
  asserting `'laya' not in sys.modules` and `'torch' not in sys.modules` right
  after this module is imported.

  IMPORTANT LIMITATION (documented per the task that added this gate, not
  discovered after the fact): this only proves the *declared build configuration*
  in the Dockerfile matches the calibration's own recorded "revision" field -- it
  does NOT prove the container actually running right now was built from that
  exact Dockerfile at that exact commit. A stale image, a manually re-tagged one,
  or a sidecar started some other way entirely would not be caught by this check.
  If a future laya-serve release adds a revision-reporting endpoint, this module
  is where that stronger check should replace (or supplement) the Dockerfile
  cross-check.
"""
from __future__ import annotations

import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_CALIBRATION_DIR = os.path.join(_HERE, "calibration")
if _CALIBRATION_DIR not in sys.path:
    sys.path.insert(0, _CALIBRATION_DIR)

import calibrate  # noqa: E402  (no top-level laya/torch import -- see module docstring)

DEFAULT_CALIBRATION_FILE = os.path.join(_CALIBRATION_DIR, "laya-calibration.json")
# agent/scripts/jev/.. -> agent/scripts, ../.. -> agent, ../../.. -> <repo root>,
# then dockers/laya.Dockerfile.
DEFAULT_DOCKERFILE_PATH = os.path.join(_HERE, "..", "..", "..", "dockers", "laya.Dockerfile")


def _load_json(path: str):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _safe_check_dockerfile_revision(dockerfile_path: str, expected_revision: str):
    """Wraps `calibrate.check_dockerfile_revision()` so ANY exception it might
    raise while reading `dockerfile_path` (OSError/PermissionError for a
    chmod-000 file, UnicodeDecodeError for a non-UTF-8 file, or anything else)
    is treated the same as an ordinary "cannot verify" outcome -- never
    propagates.

    This closes a real, reproduced defect (Checker, revision 2 review):
    `calibrate.check_dockerfile_revision()` itself calls a plain
    `open(dockerfile_path, encoding="utf-8").read()` with no try/except of its
    own (it is a standalone script meant to fail loudly when run by hand), so a
    non-UTF-8 or permission-denied Dockerfile previously propagated an
    uncaught exception all the way out of `load_verified_calibration()` (which
    had no try/except around this call), out of `guard_advisor.apply()` /
    `tier_advisor.advise()` / `evidence_reducer._reducer_rank_enabled()`, and
    crashed the calling process entirely -- for `decide.py` specifically, an
    uncaught exception here meant `main()` never reached `_out()`, decide.py
    exited non-zero with an empty stdout, and every one of the three shims'
    own "decide.py itself is unreachable" fallback then kicked in and returned
    a blanket ALLOW (claude's `|| exit 0`, agy's `except Exception: return
    {"decision": "allow"}`, pi's `{decision: "allow"}` fallback) -- silently
    downgrading a deterministic "ask" (or, in principle, any non-"block"
    decision) to "allow". Every caller in this module family must now survive
    this without raising (I-3's fail-to-deterministic promise applied to the
    revision-check step itself, not just to the Laya HTTP call)."""
    try:
        return calibrate.check_dockerfile_revision(dockerfile_path, expected_revision)
    except Exception as exc:  # noqa: BLE001 - any read/parse failure is "cannot verify"
        return "error", "exception reading %s: %r" % (dockerfile_path, exc)


def _all_disabled(data: dict) -> dict:
    """Return a copy of `data` with every capability's "enabled" forced to
    `False` (I-13's "縮小側" / reduced-permission state) -- every other field
    (metrics, threshold) is preserved unchanged for diagnostics."""
    out = dict(data)
    caps = out.get("capabilities")
    if isinstance(caps, dict):
        out["capabilities"] = {
            name: ({**entry, "enabled": False} if isinstance(entry, dict) else entry)
            for name, entry in caps.items()
        }
    return out


def load_verified_calibration(calibration_file=None, dockerfile_path=None):
    """Load laya-calibration.json and apply the I-13 revision gate.

    Returns:
      - None if the calibration file itself is missing/malformed (no
        "capabilities" dict) -- the pre-existing fail-open-to-deterministic path
        every caller already has for "calibration unreadable".
      - The full calibration dict, UNCHANGED, if the file's own "revision" field
        is present and matches `dockers/laya.Dockerfile`'s pinned
        `LAYA_HF_REVISION` (or the legacy `LAYA_HF_EXPECTED_SHA`) build-arg.
      - The same dict with every capability's "enabled" forced to `False`
        otherwise -- covers: no "revision" field recorded, the Dockerfile
        doesn't exist, the Dockerfile exists but declares neither build-arg
        name, or the Dockerfile's pinned value does not match. This is
        deliberately NOT the same as returning None: the metrics/thresholds
        recorded in the file are still meaningful for a human to read, only the
        "enabled" bits are forced closed.
    """
    try:
        calibration_file = calibration_file or DEFAULT_CALIBRATION_FILE
        data = _load_json(calibration_file)
        if not isinstance(data, dict) or not isinstance(data.get("capabilities"), dict):
            return None

        expected_revision = data.get("revision")
        if not isinstance(expected_revision, str) or not expected_revision:
            return _all_disabled(data)

        dockerfile_path = dockerfile_path or DEFAULT_DOCKERFILE_PATH
        status, _message = _safe_check_dockerfile_revision(dockerfile_path, expected_revision)
        if status != "ok":
            return _all_disabled(data)
        return data
    except Exception:
        # Defense in depth beyond _safe_check_dockerfile_revision's own catch
        # (e.g. an unexpected _all_disabled/_load_json failure on a shape this
        # module didn't anticipate) -- this function's whole contract is "never
        # raises", matching evidence_reducer.reduce_text()'s own whole-body
        # try/except pattern. When the calibration itself was loaded (`data` is
        # a valid dict) but something later failed, the safe answer is "cannot
        # verify" -> all capabilities disabled, not "crash" and not "assume
        # verified" -- re-attempt the disabled view from `data` if we have it,
        # otherwise fail all the way to None (the same as calibration being
        # unreadable in the first place).
        try:
            return _all_disabled(data) if isinstance(data, dict) else None
        except Exception:
            return None
