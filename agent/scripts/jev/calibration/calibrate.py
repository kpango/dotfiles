#!/usr/bin/env python3
"""Calibrate which System-1 (Laya) permissions are allowed to act, per CONTEXT.md
"ai-env-deepresearch-overhaul" Addendum I-13: each guard/tier/reducer permission is
enabled only when the corresponding held-out metric in the table there is met, using
calibration data in this directory (guard.jsonl, tier.jsonl, loglines.jsonl).

This script needs `laya` (>=0.3.11) and `torch` -- NOT stdlib-only -- and is
deliberately never imported by the repo's ordinary (laya-free) test suite. Run it
directly with a Python that has laya/torch installed:

    python3 agent/scripts/jev/calibration/calibrate.py \\
        --model-dir /path/to/local/laya-snapshot \\
        --out agent/scripts/jev/calibration/laya-calibration.json

Design (do not deviate without updating CONTEXT.md):
  - Fixed seed (SPLIT_SEED), stratified 50/50 calib/held-out split per dataset (I-13:
    "コーディング領域の held-out 較正データ"). Thresholds/operating points are chosen
    on the calib half only; every enable/disable decision and every metric recorded
    in the output is computed on the held-out half. Never peek at held-out before
    freezing a threshold -- that would be leakage (explicitly forbidden by the task).
  - The model is fetched at a *pinned* revision (REVISION below, matched against
    `dockers/laya.Dockerfile`'s `ARG LAYA_HF_REVISION` when that file exists in this
    worktree -- the legacy `LAYA_HF_EXPECTED_SHA` name is still accepted as a
    backward-compatible fallback during the T16/T17 migration window, see
    `read_dockerfile_pinned_revision()`) via `huggingface_hub.snapshot_download`, then
    loaded from the local snapshot directory with `laya.load()` -- never
    `laya.load("convaiinnovations/laya")` directly, which would float to whatever
    revision the Hub currently serves.
  - Questions (instructions/criteria) come from `agent/scripts/jev/questions.py`, the
    same module the production hook path will import, so calibration measures the
    exact question text that goes into production.
  - Bad results are recorded as-is: a capability whose held-out metrics miss the bar
    in CONTEXT.md's table is written out with "enabled": false and its measured
    metrics, never silently omitted or threshold-shopped to flip it to true.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import sys
import time
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
JEV_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, JEV_DIR)

import questions as Q  # noqa: E402  (agent/scripts/jev/questions.py, stdlib-only)

MODEL_REPO = "convaiinnovations/laya"
# Pinned revision -- must match dockers/laya.Dockerfile's `ARG LAYA_HF_REVISION` (that
# file is added by a separate task, T16; when present in this worktree, main()
# cross-checks it via check_dockerfile_revision() below and refuses to proceed on a
# mismatch rather than silently calibrating against the wrong checkpoint). The legacy
# `LAYA_HF_EXPECTED_SHA` build-arg name is accepted as a backward-compatible fallback
# during the T16/T17 migration window -- see read_dockerfile_pinned_revision().
REVISION = "bf2e02ac0a5f86d70c84adedd87c1c1dccdde0bc"
ALLOW_PATTERNS = ["rl_agent_config.json", "model.safetensors", "tokenizer/*", "encoder/*"]

# Build-arg names that may carry the pinned revision in dockers/laya.Dockerfile, most
# preferred first. LAYA_HF_REVISION is the current name (T16); LAYA_HF_EXPECTED_SHA is
# accepted only as a transitional fallback and should be removed once no Dockerfile in
# this repo still uses it.
_DOCKERFILE_REVISION_VARS = ("LAYA_HF_REVISION", "LAYA_HF_EXPECTED_SHA")

# Fixed so the calib/held-out split is exactly reproducible across runs (CONTEXT.md
# I-13: thresholds are chosen on calib only, so the split itself must be pinned, not
# re-randomized on every invocation).
SPLIT_SEED = 20260924

DEFAULT_BATCH_SIZE = 32


# ---------------------------------------------------------------------------
# Data loading + reproducible stratified split
# ---------------------------------------------------------------------------


def load_jsonl(path: str) -> list:
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def stratified_split(rows: list, label_fn, seed: int):
    """Split `rows` ~50/50 into (calib, held_out), stratified by `label_fn(row)` so
    every label's ratio is preserved in both halves. Deterministic given `seed`:
    each label group is shuffled with its own `random.Random(seed)` instance (fresh
    per group, not a single shared generator, so adding/removing rows from one group
    never perturbs another group's split)."""
    groups: dict = {}
    for row in rows:
        groups.setdefault(label_fn(row), []).append(row)

    calib, held_out = [], []
    for label in sorted(groups, key=repr):
        group = list(groups[label])
        random.Random(seed).shuffle(group)
        half = (len(group) + 1) // 2  # calib gets the extra one on an odd count
        calib.extend(group[:half])
        held_out.extend(group[half:])
    return calib, held_out


# ---------------------------------------------------------------------------
# Stdlib AUROC (Mann-Whitney rank-sum formulation, average-rank tie handling) --
# deliberately not scipy/sklearn: this script's only heavy dependency is laya/torch
# themselves, not a numerics stack pulled in solely for one metric.
# ---------------------------------------------------------------------------


def auroc(scores, labels):
    """AUROC of `scores` predicting boolean `labels`, or None if either class is
    empty (AUROC is undefined with only one class present)."""
    pairs = sorted(zip(scores, labels), key=lambda sl: sl[0])
    n = len(pairs)
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j < n and pairs[j][0] == pairs[i][0]:
            j += 1
        avg_rank = (i + 1 + j) / 2.0  # 1-indexed rank, averaged over the tied block
        for k in range(i, j):
            ranks[k] = avg_rank
        i = j
    n_pos = sum(1 for _, label in pairs if label)
    n_neg = n - n_pos
    if n_pos == 0 or n_neg == 0:
        return None
    sum_ranks_pos = sum(r for r, (_, label) in zip(ranks, pairs) if label)
    return (sum_ranks_pos - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def youden_threshold(scores, labels):
    """Threshold (from among the observed `scores`) maximizing TPR - FPR (Youden's J)
    on (scores, labels). Used only to pick guard_strengthen's *reported* operating
    point -- the AUROC gate itself is threshold-free."""
    n_pos = sum(1 for label in labels if label)
    n_neg = len(labels) - n_pos
    if n_pos == 0 or n_neg == 0:
        return 0.5, 0.0
    best_t, best_j = 0.5, -1.0
    for t in sorted(set(scores)):
        tp = sum(1 for s, label in zip(scores, labels) if label and s >= t)
        fp = sum(1 for s, label in zip(scores, labels) if not label and s >= t)
        tpr = tp / n_pos
        fpr = fp / n_neg
        j = tpr - fpr
        if j > best_j:
            best_j, best_t = j, t
    return best_t, best_j


def rate_at_threshold(scores, labels, threshold):
    n_pos = sum(1 for label in labels if label)
    n_neg = len(labels) - n_pos
    tp = sum(1 for s, label in zip(scores, labels) if label and s >= threshold)
    fp = sum(1 for s, label in zip(scores, labels) if not label and s >= threshold)
    return {
        "recall": (tp / n_pos) if n_pos else None,
        "false_positive_rate": (fp / n_neg) if n_neg else None,
        "n_pos": n_pos,
        "n_neg": n_neg,
        "tp": tp,
        "fp": fp,
    }


# ---------------------------------------------------------------------------
# dockers/laya.Dockerfile revision cross-check
#
# Pulled out as standalone functions (rather than inlined in main()) so
# test_calibration.py can import and exercise this exact matching/mismatch logic
# against synthetic Dockerfile fragments, independent of whether the real
# dockers/laya.Dockerfile exists in this worktree (it is added by T16, a separate
# task). This module has no top-level laya/torch import, so importing it here is
# safe from a laya-free test environment.
# ---------------------------------------------------------------------------


def read_dockerfile_pinned_revision(contents: str):
    """Return (var_name, sha) for the pinned Laya revision declared in a
    Dockerfile's text, or None if neither build-arg name is present.

    Prefers `LAYA_HF_REVISION` (the current name, T16); falls back to the legacy
    `LAYA_HF_EXPECTED_SHA` only as a transitional compatibility measure -- if both
    are present (e.g. mid-migration), `LAYA_HF_REVISION` wins.
    """
    for var_name in _DOCKERFILE_REVISION_VARS:
        match = re.search(re.escape(var_name) + r"=([0-9a-fA-F]{40})", contents)
        if match:
            return var_name, match.group(1)
    return None


def check_dockerfile_revision(dockerfile_path: str, expected_revision: str):
    """Cross-check `expected_revision` against `dockerfile_path`'s pinned-revision
    build-arg, if that file exists. Returns (status, message):

      "ok"    -- the file exists and its pinned revision matches `expected_revision`
      "fatal" -- the file exists but its pinned revision does NOT match -- the
                 caller should treat this as a hard failure and refuse to proceed,
                 rather than silently calibrating against a possibly different
                 checkpoint than production will pull
      "skip"  -- the file doesn't exist, or exists but declares neither the current
                 nor the legacy build-arg name -- nothing to cross-check against
    """
    if not os.path.exists(dockerfile_path):
        return "skip", "%s does not exist; skipping the cross-check" % dockerfile_path
    with open(dockerfile_path, encoding="utf-8") as f:
        contents = f.read()
    found = read_dockerfile_pinned_revision(contents)
    if found is None:
        return "skip", (
            "%s exists but declares neither LAYA_HF_REVISION nor the legacy "
            "LAYA_HF_EXPECTED_SHA; skipping the cross-check" % dockerfile_path
        )
    var_name, sha = found
    if sha != expected_revision:
        return "fatal", (
            "%s=%s in %s does not match the pinned revision %s"
            % (var_name, sha, dockerfile_path, expected_revision)
        )
    return "ok", "%s's %s matches %s" % (dockerfile_path, var_name, expected_revision)


# ---------------------------------------------------------------------------
# --model-dir revision provenance check
#
# T17 attempt 3 (an independent Checker): passing --model-dir skipped
# snapshot_download entirely, and the output's "revision" field was written from
# the hardcoded REVISION constant unconditionally -- so a --model-dir pointing at a
# stale or wrong-commit snapshot would silently be recorded as the pinned revision,
# with nothing to catch the mismatch. Fixed by resolving the *actual* commit the
# directory was fetched at from huggingface_hub's own on-disk layout (verified
# against the installed huggingface_hub's source, not guessed -- see each check
# below) and refusing to proceed, the same way check_dockerfile_revision() already
# refuses on a Dockerfile mismatch, rather than recording an unverified claim.
# ---------------------------------------------------------------------------

# huggingface_hub's own definition of what a resolved commit hash looks like
# (huggingface_hub.file_download.REGEX_COMMIT_HASH, same pattern).
_COMMIT_HASH_RE = re.compile(r"^[0-9a-f]{40}$")


def resolve_model_dir_revision(model_dir: str):
    """Best-effort recovery of the actual commit hash a local model directory was
    fetched at, from huggingface_hub's own on-disk layout:

      1. Cache-mode `snapshot_download()` layout: the returned directory is
         `<cache>/models--<org>--<repo>/snapshots/<commit_hash>/` -- the snapshot
         directory's own name IS the resolved commit hash (huggingface_hub's
         `_snapshot_download.py`: `snapshot_folder = os.path.join(storage_folder,
         "snapshots", commit_hash)`). Symlinks are resolved first since some
         cache layouts hand back a symlinked path.
      2. `local_dir=`/`hf_hub_download(local_dir=...)` layout: per-file metadata at
         `<model_dir>/.cache/huggingface/download/**/*.metadata`, whose first line
         is that file's commit_hash (huggingface_hub's `_local_folder.py` module
         docstring documents this exact 3-line format: commit_hash / etag /
         timestamp). If every metadata file agrees on one commit hash, that's the
         directory's revision.

    Returns (resolved_sha_or_None, source). `source` is a short human-readable tag
    for diagnostics; `resolved_sha_or_None` is None if neither layout yielded a
    single, unambiguous commit hash -- callers must treat that as unverifiable, not
    as a pass.
    """
    real_dir = os.path.realpath(model_dir)
    basename = os.path.basename(real_dir.rstrip(os.sep))
    if _COMMIT_HASH_RE.match(basename):
        return basename, "snapshot directory name (%s)" % real_dir

    metadata_root = os.path.join(model_dir, ".cache", "huggingface", "download")
    if os.path.isdir(metadata_root):
        commit_hashes = set()
        for dirpath, _dirnames, filenames in os.walk(metadata_root):
            for fname in filenames:
                if not fname.endswith(".metadata"):
                    continue
                try:
                    with open(os.path.join(dirpath, fname), encoding="utf-8") as f:
                        first_line = f.readline().strip()
                except OSError:
                    continue
                if _COMMIT_HASH_RE.match(first_line):
                    commit_hashes.add(first_line)
        if len(commit_hashes) == 1:
            return next(iter(commit_hashes)), "local_dir download metadata (%s)" % metadata_root
        if len(commit_hashes) > 1:
            return None, "local_dir download metadata disagrees across files: %s" % ", ".join(sorted(commit_hashes))

    return None, "neither a snapshots/<sha> directory name nor local_dir download metadata was found under %s" % model_dir


def check_model_dir_revision(model_dir: str, expected_revision: str):
    """Cross-check `expected_revision` against `model_dir`'s actual on-disk
    provenance. Returns (status, message) with the same three-way contract as
    `check_dockerfile_revision()`:

      "ok"    -- the directory's resolved commit hash matches `expected_revision`
      "fatal" -- the directory's resolved commit hash does NOT match, OR no commit
                 hash could be resolved at all -- the caller must refuse to proceed
                 rather than record an unverified revision as if it were pinned
      "skip"  -- not applicable when a model_dir is given (kept for symmetry with
                 check_dockerfile_revision(); never actually returned here)
    """
    resolved, source = resolve_model_dir_revision(model_dir)
    if resolved is None:
        return "fatal", (
            "could not verify which commit --model-dir=%s was actually fetched at (%s); "
            "refusing to record revision=%s as if it were verified -- re-fetch via "
            "snapshot_download's normal cache layout, or pass a directory this check "
            "can verify" % (model_dir, source, expected_revision)
        )
    if resolved != expected_revision:
        return "fatal", (
            "--model-dir=%s resolves to commit %s (via %s), which does not match the "
            "pinned revision %s" % (model_dir, resolved, source, expected_revision)
        )
    return "ok", "--model-dir=%s resolves to the pinned revision %s (via %s)" % (model_dir, expected_revision, source)


# ---------------------------------------------------------------------------
# Model loading + batched prediction
# ---------------------------------------------------------------------------


def fetch_model_dir(model_dir_override, token=None):
    if model_dir_override:
        return model_dir_override
    from huggingface_hub import snapshot_download

    return snapshot_download(
        repo_id=MODEL_REPO,
        revision=REVISION,
        allow_patterns=ALLOW_PATTERNS,
        token=token,
    )


def predict_all(agent, states, questions_def, batch_size):
    return agent.predict_batch(states, questions_def, batch_size=batch_size)


# ---------------------------------------------------------------------------
# Per-capability calibration
# ---------------------------------------------------------------------------


def calibrate_guard(agent, calib_rows, heldout_rows, batch_size):
    def scores_and_labels(rows):
        states = [Q.guard_state(r["command"]) for r in rows]
        results = predict_all(agent, states, Q.GUARD_QUESTIONS, batch_size)
        scores = [res["answers"][Q.GUARD_QUESTION_ID]["noul"] for res in results]
        labels = [bool(r["dangerous"]) for r in rows]
        return scores, labels

    calib_scores, calib_labels = scores_and_labels(calib_rows)
    heldout_scores, heldout_labels = scores_and_labels(heldout_rows)

    # --- guard_strengthen (allow -> ask): AUROC >= 0.90 on held-out ---
    strengthen_threshold, _ = youden_threshold(calib_scores, calib_labels)
    ho_auroc = auroc(heldout_scores, heldout_labels)
    strengthen_enabled = ho_auroc is not None and ho_auroc >= 0.90
    strengthen_at_threshold = rate_at_threshold(heldout_scores, heldout_labels, strengthen_threshold)

    # --- guard_deny (single deny): on calib, pick the lowest threshold above every
    # calib safe score (so calib false-positive count is 0 by construction); gate is
    # "0 safe held-out and >=0.5 dangerous held-out recall AT THAT THRESHOLD".
    calib_safe_scores = [s for s, label in zip(calib_scores, calib_labels) if not label]
    deny_threshold = (max(calib_safe_scores) + 1e-4) if calib_safe_scores else 1.0 + 1e-4
    deny_at_threshold = rate_at_threshold(heldout_scores, heldout_labels, deny_threshold)
    deny_enabled = (
        deny_at_threshold["fp"] == 0
        and deny_at_threshold["recall"] is not None
        and deny_at_threshold["recall"] >= 0.5
    )

    # --- guard_relax (ask -> allow): on calib, pick the highest threshold below
    # every calib dangerous score (so calib missed-dangerous count is 0 by
    # construction); gate is "0 held-out dangerous commands score below it" (a
    # dangerous command scoring below the relax cutoff would be silently relaxed to
    # allow -- a miss).
    calib_dangerous_scores = [s for s, label in zip(calib_scores, calib_labels) if label]
    relax_threshold = (min(calib_dangerous_scores) - 1e-4) if calib_dangerous_scores else -1e-4
    ho_missed_dangerous = sum(
        1 for s, label in zip(heldout_scores, heldout_labels) if label and s < relax_threshold
    )
    ho_n_dangerous = sum(1 for label in heldout_labels if label)
    relax_enabled = ho_missed_dangerous == 0

    return {
        "guard_strengthen": {
            "enabled": strengthen_enabled,
            "threshold": strengthen_threshold,
            "metrics": {
                "held_out_auroc": ho_auroc,
                "held_out_recall_at_threshold": strengthen_at_threshold["recall"],
                "held_out_false_positive_rate_at_threshold": strengthen_at_threshold["false_positive_rate"],
                "condition": "held_out_auroc >= 0.90",
            },
        },
        "guard_deny": {
            "enabled": deny_enabled,
            "threshold": deny_threshold,
            "metrics": {
                "held_out_safe_false_positives": deny_at_threshold["fp"],
                "held_out_dangerous_recall": deny_at_threshold["recall"],
                "held_out_n_safe": deny_at_threshold["n_neg"],
                "held_out_n_dangerous": deny_at_threshold["n_pos"],
                "condition": "held_out_safe_false_positives == 0 and held_out_dangerous_recall >= 0.5",
            },
        },
        "guard_relax": {
            "enabled": relax_enabled,
            "threshold": relax_threshold,
            "metrics": {
                "held_out_missed_dangerous": ho_missed_dangerous,
                "held_out_n_dangerous": ho_n_dangerous,
                "condition": "held_out_missed_dangerous == 0",
            },
        },
        "_diagnostics": {
            "calib_n": len(calib_rows),
            "held_out_n": len(heldout_rows),
        },
    }


def calibrate_tier(agent, calib_rows, heldout_rows, batch_size):
    def predict(rows):
        states = [Q.tier_state(r["description"]) for r in rows]
        results = predict_all(agent, states, Q.TIER_QUESTIONS, batch_size)
        return [res["answers"][Q.TIER_QUESTION_ID]["choice"] for res in results]

    heldout_pred = predict(heldout_rows)
    true_tiers = [r["tier"] for r in heldout_rows]

    n = len(heldout_rows)
    correct = sum(1 for p, t in zip(heldout_pred, true_tiers) if p == t)
    accuracy = correct / n if n else None

    def rank(tier_name):
        return Q.TIER_LEVELS.index(tier_name)

    over = sum(1 for p, t in zip(heldout_pred, true_tiers) if rank(p) > rank(t))
    over_rate = over / n if n else None

    per_class = {}
    for level in Q.TIER_LEVELS:
        idx = [i for i, t in enumerate(true_tiers) if t == level]
        if idx:
            per_class[level] = sum(1 for i in idx if heldout_pred[i] == true_tiers[i]) / len(idx)
        else:
            per_class[level] = None

    enabled = accuracy is not None and accuracy >= 0.70 and over_rate is not None and over_rate <= 0.25

    return {
        "tier_raise": {
            "enabled": enabled,
            "metrics": {
                "held_out_accuracy": accuracy,
                "held_out_over_tier_rate": over_rate,
                "held_out_per_class_accuracy": per_class,
                "held_out_n": n,
                "condition": "held_out_accuracy >= 0.70 and held_out_over_tier_rate <= 0.25",
            },
        }
    }


def calibrate_reducer(agent, calib_rows, heldout_rows, batch_size):
    # calib is intentionally unused for choosing a threshold here: the predicted
    # class is laya's own argmax over the 3-way probability simplex it already
    # returns (no free threshold to fit), so there is nothing to tune on calib for
    # this capability beyond the question text itself (frozen in questions.py).
    def predict(rows):
        states = [Q.reducer_state(r["line"]) for r in rows]
        results = predict_all(agent, states, Q.REDUCER_QUESTIONS, batch_size)
        # T18: the argmax-over-probabilities rule is centralized in
        # Q.reducer_predicted_class() (shared with evidence_reducer.py's production
        # ranking, so the two can never silently drift apart) rather than duplicated here.
        return [Q.reducer_predicted_class(res["answers"][Q.REDUCER_QUESTION_ID]["probabilities"]) for res in results]

    heldout_pred = predict(heldout_rows)
    true_labels = [r["label"] for r in heldout_rows]
    lines = [r["line"] for r in heldout_rows]

    critical_idx = [i for i, t in enumerate(true_labels) if t == "critical"]
    n_critical = len(critical_idx)

    laya_hits = sum(1 for i in critical_idx if heldout_pred[i] == "critical")
    laya_recall = (laya_hits / n_critical) if n_critical else None

    det_predicted_idx = [i for i in range(len(heldout_rows)) if Q.is_deterministic_critical(lines[i])]
    det_predicted_n = len(det_predicted_idx)
    det_hits = sum(1 for i in critical_idx if Q.is_deterministic_critical(lines[i]))
    det_recall = (det_hits / n_critical) if n_critical else None
    # Reference-only (T17 attempt 5): NOT part of the enable/disable condition below.
    # The deterministic pattern is deliberately a recall-first safety floor (see
    # questions.py's design notes) -- it is expected, and accepted, to have low
    # precision (many noise/context lines also match). Recorded here purely so a
    # human reviewing this file can see how many held-out lines it over-flags,
    # without that number ever gating anything.
    det_precision = (det_hits / det_predicted_n) if det_predicted_n else None

    enabled = laya_recall is not None and det_recall is not None and laya_recall >= det_recall

    return {
        "reducer_rank": {
            "enabled": enabled,
            "metrics": {
                "held_out_laya_critical_recall": laya_recall,
                "held_out_deterministic_critical_recall": det_recall,
                "held_out_deterministic_critical_precision_reference_only": det_precision,
                "held_out_deterministic_predicted_critical_n": det_predicted_n,
                "held_out_n_critical": n_critical,
                "held_out_n": len(heldout_rows),
                "condition": "held_out_laya_critical_recall >= held_out_deterministic_critical_recall",
            },
        }
    }


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--guard", default=os.path.join(SCRIPT_DIR, "guard.jsonl"))
    parser.add_argument("--tier", default=os.path.join(SCRIPT_DIR, "tier.jsonl"))
    parser.add_argument("--loglines", default=os.path.join(SCRIPT_DIR, "loglines.jsonl"))
    parser.add_argument("--out", default=os.path.join(SCRIPT_DIR, "laya-calibration.json"))
    parser.add_argument("--model-dir", default=None, help="local snapshot dir; skips snapshot_download if given")
    parser.add_argument("--device", default=None, help="torch device (default: auto -- cuda if available)")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    parser.add_argument("--hf-token", default=None)
    args = parser.parse_args(argv)

    # JEV_DIR = <root>/agent/scripts/jev -- three levels up is <root>.
    root_dir = os.path.dirname(os.path.dirname(os.path.dirname(JEV_DIR)))
    dockerfile = os.path.normpath(os.path.join(root_dir, "dockers", "laya.Dockerfile"))
    status, message = check_dockerfile_revision(dockerfile, REVISION)
    if status == "fatal":
        print(
            "FATAL: %s -- refusing to calibrate against a possibly different "
            "checkpoint than production will pull." % message,
            file=sys.stderr,
        )
        return 2
    print(("OK: " if status == "ok" else "") + message)

    guard_rows = load_jsonl(args.guard)
    tier_rows = load_jsonl(args.tier)
    loglines_rows = load_jsonl(args.loglines)

    dataset_sha256 = {
        "guard": sha256_file(args.guard),
        "tier": sha256_file(args.tier),
        "loglines": sha256_file(args.loglines),
    }

    guard_calib, guard_heldout = stratified_split(guard_rows, lambda r: r["dangerous"], SPLIT_SEED)
    tier_calib, tier_heldout = stratified_split(tier_rows, lambda r: r["tier"], SPLIT_SEED)
    loglines_calib, loglines_heldout = stratified_split(loglines_rows, lambda r: r["label"], SPLIT_SEED)

    print(
        "guard split: calib=%d held_out=%d | tier split: calib=%d held_out=%d | "
        "loglines split: calib=%d held_out=%d"
        % (
            len(guard_calib), len(guard_heldout),
            len(tier_calib), len(tier_heldout),
            len(loglines_calib), len(loglines_heldout),
        )
    )

    t0 = time.monotonic()
    model_dir = fetch_model_dir(args.model_dir, token=args.hf_token)
    print("model_dir=%s (fetch took %.1fs)" % (model_dir, time.monotonic() - t0))

    # Verify what commit model_dir actually holds -- unconditionally, not just when
    # --model-dir is given, so a stale/corrupted cache entry from a plain
    # snapshot_download() call is caught the same way (defense in depth; see
    # check_model_dir_revision()'s docstring for why --model-dir specifically needed
    # this after previously skipping it entirely).
    status, message = check_model_dir_revision(model_dir, REVISION)
    if status == "fatal":
        print(
            "FATAL: %s -- refusing to record revision=%s as verified." % (message, REVISION),
            file=sys.stderr,
        )
        return 2
    print("OK: %s" % message)

    import torch  # local import: only needed once we actually load the model
    import laya

    device = args.device or ("cuda" if torch.cuda.is_available() else "cpu")
    t0 = time.monotonic()
    agent = laya.load(model_dir, device=device)
    print("laya.load() took %.1fs on device=%s" % (time.monotonic() - t0, agent.device))

    t0 = time.monotonic()
    guard_result = calibrate_guard(agent, guard_calib, guard_heldout, args.batch_size)
    print("guard calibration took %.1fs" % (time.monotonic() - t0))
    for cap in ("guard_strengthen", "guard_deny", "guard_relax"):
        print("  %s: enabled=%s metrics=%s" % (cap, guard_result[cap]["enabled"], guard_result[cap]["metrics"]))

    t0 = time.monotonic()
    tier_result = calibrate_tier(agent, tier_calib, tier_heldout, args.batch_size)
    print("tier calibration took %.1fs" % (time.monotonic() - t0))
    print("  tier_raise: enabled=%s metrics=%s" % (tier_result["tier_raise"]["enabled"], tier_result["tier_raise"]["metrics"]))

    t0 = time.monotonic()
    reducer_result = calibrate_reducer(agent, loglines_calib, loglines_heldout, args.batch_size)
    print("reducer calibration took %.1fs" % (time.monotonic() - t0))
    print("  reducer_rank: enabled=%s metrics=%s" % (reducer_result["reducer_rank"]["enabled"], reducer_result["reducer_rank"]["metrics"]))

    capabilities = {}
    capabilities.update({k: v for k, v in guard_result.items() if not k.startswith("_")})
    capabilities.update(tier_result)
    capabilities.update(reducer_result)

    output = {
        "model_repo": MODEL_REPO,
        "revision": REVISION,
        "laya_version": laya.__version__,
        "dataset_sha256": dataset_sha256,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "split_seed": SPLIT_SEED,
        "device": str(agent.device),
        "temperature_fitting": {
            "used": False,
            "reason": (
                "laya 0.3.11's public API (laya.Agent) exposes only the temperature "
                "the checkpoint already ships (self.temperature / "
                "self.temperature_by_options, applied automatically); no separate "
                "domain temperature-fitting entry point was found to fit on calib "
                "data, so none was used. The checkpoint's own calibration is used "
                "as-is."
            ),
        },
        "capabilities": capabilities,
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    print("wrote %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
