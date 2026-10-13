#!/bin/sh
# Entrypoint for the laya-serve sidecar (dockers/laya.Dockerfile). Validates CUDA is
# actually usable for *real inference*, not just "a CDI device got attached" or "a bare
# tensor op works" -- before telling laya-serve/Router to use it -- falling back to
# LAYA_DEVICE=cpu instead of crash-looping under `--restart always` when the driver/
# toolkit combination fails at some later, model-specific CUDA call. A bare
# `torch.zeros(1, device="cuda") + 1` (this self-test's own earlier version) does NOT
# exercise that: laya's English checkpoint JIT-compiles a Triton-generated kernel shim
# via a plain C compiler on its *first real forward pass* (ModernBERT's RoPE
# bmm_outer_product custom op -- see dockers/laya.Dockerfile's gcc/libc6-dev install
# comment), and a bare tensor add never reaches that code path. Nor does laya's own
# runtime OOM fallback help here (`Agent._forward`, laya/agent.py): it only retries on
# CPU for a RuntimeError/OutOfMemoryError whose message contains "memory" or "cuda",
# so a differently-worded failure (e.g. Triton's "Failed to find C compiler") would
# otherwise reach every request as an HTTP 500 with LAYA_DEVICE still cuda, and
# reproduce on every restart if preload itself fails during the same code path -- a
# real crash loop, not a graceful fallback. This self-test instead actually loads the
# baked checkpoint on cuda and runs one real prediction (laya.load + .predict), which
# hits that same forward pass; the several extra seconds of startup time in the
# CUDA-good case fixes that gap. If LAYA_DEVICE is explicitly set to "cpu" (e.g. no GPU
# was detected host-side, see zsh/20-docker.zsh's devrun()), this check is skipped
# entirely. `timeout` (coreutils, present in this image's python:3.12-slim base) bounds
# a hang in the model load/forward pass itself, not just an exception from it.
set -eu

if [ "${LAYA_DEVICE:-}" != "cpu" ]; then
	if timeout "${LAYA_CUDA_SELFTEST_TIMEOUT:-180}" python3 -c '
import sys

try:
    import torch
    if not torch.cuda.is_available():
        sys.exit(1)

    import laya

    agent = laya.load("convaiinnovations/laya", device="cuda")
    result = agent.predict(
        "laya-entrypoint CUDA self-test",
        {"q": {"type": "choice", "instructions": "Pick one.", "criteria": {"a": "A", "b": "B"}}},
    )
    sys.exit(0 if isinstance(result, dict) and "q" in result.get("answers", {}) else 1)
except Exception as exc:
    print("laya-entrypoint: CUDA self-test raised: %r" % (exc,), file=sys.stderr)
    sys.exit(1)
'; then
		export LAYA_DEVICE=cuda
	else
		echo "laya-entrypoint: CUDA unavailable or failed the real-inference self-test (timed out after ${LAYA_CUDA_SELFTEST_TIMEOUT:-180}s or raised) -- falling back to LAYA_DEVICE=cpu" >&2
		export LAYA_DEVICE=cpu
	fi
fi

exec laya-serve
