# syntax = docker/dockerfile:latest
# Standalone laya-serve sidecar with the English checkpoint baked in at build time
# (offline-ready on first start, same precedent as dockers/ollama.Dockerfile -- see
# zsh/20-docker.zsh's devrun()/devkill() for how the two sidecars are started/stopped
# alongside the `dev` container).
#
# Backend for the "System-1 judgment" layer (CONTEXT.md "ai-env-deepresearch-overhaul"
# addendum, I-11/I-12): laya-serve (PyPI `laya[serve]`) implements the same
# POST /v1/systemone wire protocol as the third-party Jev API, so a Jev API client is
# expected to talk to this container unchanged -- only TYPESAFE_API_URL is pointed at
# the loopback endpoint below instead of api.typesafe.ai. `agent/scripts/jev/jev_client.py`
# is that client.
#
# Base image (T16 trial 2, after an actual `docker build` + independent Checker both
# failed trial 1's `pytorch/pytorch:*-runtime` base): `python:3.12-slim`. Two problems
# with the previous base, both found in that trial-1 build + Checker run (2026-09-24;
# not covered by an automated test): (1) its newer
# `-runtime` tags are Ubuntu 24.04, whose apt-provided pip refuses a plain `pip install`
# outside a venv (PEP 668 "externally-managed-environment", exit 1), and Ubuntu 24.04
# ships a pre-existing uid/gid 1000 `ubuntu` user that collides with this file's own
# USER_ID/GROUP_ID=1000 useradd (the Makefile always passes 1000 here); (2) it publishes
# only a linux/amd64 manifest, not a manifest list, unlike this repo's other
# docker/build/% images (`DOCKER_BUILDER_PLATFORM=linux/amd64,linux/arm64/v8`,
# Makefile.d/variables.mk) and the ollama sidecar precedent -- the macOS devrun() branch
# needs an arm64 pull. `python:3.12-slim` is confirmed multi-arch (`docker buildx
# imagetools inspect python:3.12-slim` lists both linux/amd64 and linux/arm64/v8), and a
# venv (below) sidesteps PEP 668 regardless of base. torch itself needs no separate
# per-arch handling either, but not for the reason an earlier draft of this comment
# claimed: PyPI *does* publish CUDA-enabled wheels for linux/arm64 (torch 2.14.0, triton
# 3.8.0, and its nvidia-cudnn-cu13/nvidia-nccl-cu13/etc. dependencies all ship
# `manylinux_*_aarch64` wheels -- confirmed via `GET pypi.org/pypi/<pkg>/<version>/json`,
# and torch's own `requires_dist` gates those CUDA deps on `platform_system == "Linux"`
# only, not on x86_64 -- so the identical `pip install laya[serve]` pulls the same CUDA
# runtime on both linux/amd64 and linux/arm64/v8). The behavior that actually makes this
# arch-independent is runtime, not install-time: torch no-ops CUDA ops to CPU on a host
# with no visible GPU regardless of which arch's wheel got installed, and the CDI-vs-none
# `docker run` flags in zsh/20-docker.zsh's devrun() (and this file's own entrypoint
# CUDA self-test) are what actually decide cuda-vs-cpu at container start, not the arch
# of the wheel resolved at build time.
ARG BASE_IMAGE=python:3.12-slim
ARG LAYA_VERSION=0.3.11
# HF revision to bake in -- must be a full 40-character commit sha, not a branch/tag name
# (T16 trial 4; dockers/laya-fetch-checkpoint.py fails the build otherwise, empty
# included). Trial 3 resolved the floating ref "main" and compared it against a
# separately-tracked LAYA_HF_EXPECTED_SHA; that broke every time upstream's main moved
# (observed 5 times across this file's own review trials: 80e2e0e8 -> fe2b7719 ->
# dbbc634e -> bf2e02ac -> cf7c54c0, each confirmed live against the HF API) even though
# the pinned checkpoint's *content* never changed for this image. Requesting the commit
# sha directly as the revision removes the floating ref entirely, so there is nothing
# left for upstream to move out from under this pin, and collapses what used to be two
# args that could disagree into one.
#
# This is also a hard correctness requirement, not just a build-stability one:
# `agent/scripts/jev/calibration/laya-calibration.json` (T17) calibrates its outputs
# against this exact commit. If you intentionally move
# to a newer checkpoint, this value and that file's `revision` field MUST be updated
# together and the model recalibrated -- deploying a different commit under the same
# checkpoint name would silently apply T17's calibration to a different model.
#
# The laya-fetch stage below always (re)writes the local cache's `refs/main` file to
# point at this commit -- regardless of it not literally being named "main" -- so
# laya's own revision-less, offline `snapshot_download()` call at container-start
# preload time still resolves it correctly (T16 review finding #3; trial 1 only warned
# and left the container to fail at runtime).
ARG LAYA_HF_REVISION=bf2e02ac0a5f86d70c84adedd87c1c1dccdde0bc

# --- fetch stage: pull only the English checkpoint's files into the HF cache -----------
FROM ${BASE_IMAGE} AS laya-fetch
ARG LAYA_HF_REVISION
ENV HF_HUB_DISABLE_TELEMETRY=1 \
    LAYA_HF_REVISION=${LAYA_HF_REVISION}
# huggingface_hub is also a laya[serve] dependency; installed standalone here so a bad
# revision/network failure surfaces at this narrow RUN instead of deep inside laya-serve's
# own startup path later. python:3.12-slim's pip is not PEP-668-restricted (that
# restriction is an OS-vendored-Python thing, e.g. Debian/Ubuntu's apt python3 -- this is
# the official upstream Python build), so no venv is needed in this short-lived stage.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir "huggingface_hub>=0.20.0"
# hadolint's Dockerfile parser (language-docker) does not support BuildKit's RUN/COPY
# heredoc-to-file syntax at all (confirmed: it fails to parse even a minimal, textbook-
# correct `COPY <<EOF /path` example), so the fetch/verify/refs-patch script is a real
# sibling file instead of inline heredoc content.
COPY dockers/laya-fetch-checkpoint.py /tmp/fetch_laya_checkpoint.py
# Deliberately NOT `--mount=type=cache,target=/root/.cache/huggingface`: a BuildKit
# cache mount persists across builds (even across different LAYA_HF_REVISION values,
# since the mount itself isn't keyed on the ARGs baked into this stage's ENV), so
# anything already resident from a prior build's snapshot_download stays in the mount
# and gets swept up by a blanket copy of the whole cache dir -- found by building this
# stage twice with two different revisions during T16's review trials (2026-09-24; not
# covered by an automated test) and finding both snapshots present afterwards. That
# defeats the fail-closed guard below: a build can succeed the
# commit-sha check for the pinned revision while *also* baking in an unpinned,
# unverified snapshot from an earlier build. Downloading straight to this stage's own
# writable layer instead means the only thing here is whatever this exact RUN (keyed on
# the LAYA_HF_REVISION ENV value set above, so a different value invalidates and
# redownloads) actually fetched and verified.
RUN python3 /tmp/fetch_laya_checkpoint.py \
    && cp -a /root/.cache/huggingface /root/huggingface-baked

# --- runtime stage -----------------------------------------------------------------------
FROM ${BASE_IMAGE}
ARG EMAIL=kpango@vdaas.org
ARG LAYA_VERSION
ARG USER_ID=1000
ARG GROUP_ID=1000
LABEL maintainer="kpango <${EMAIL}>"

# Non-root: laya-serve has no privileged needs (no ports < 1024, no host device access --
# GPU access is granted at `docker run` time via CDI, not by uid). Defensively remove any
# pre-existing account already claiming USER_ID/GROUP_ID first (same idiom as
# dockers/env.Dockerfile's `userdel ubuntu` -- this repo's base images have been observed to
# ship a conflicting uid/gid 1000 before, see the file-header comment above); harmless no-op
# on a base with no such account.
RUN existing_group="$(getent group "${GROUP_ID}" | cut -d: -f1 || true)"; \
    if [ -n "${existing_group}" ] && [ "${existing_group}" != "laya" ]; then groupdel "${existing_group}" || true; fi; \
    existing_user="$(getent passwd "${USER_ID}" | cut -d: -f1 || true)"; \
    if [ -n "${existing_user}" ] && [ "${existing_user}" != "laya" ]; then userdel -f "${existing_user}" || true; fi; \
    groupadd --gid "${GROUP_ID}" laya \
    && useradd --uid "${USER_ID}" --gid "${GROUP_ID}" --create-home --shell /usr/sbin/nologin laya

# gcc + libc6-dev: torch 2.14's CUDA custom-op dispatch (`torch._native`, e.g.
# ModernBERT's RoPE `bmm_outer_product` kernel, which laya's English checkpoint hits on
# its very first forward pass) JIT-compiles a small Triton-generated shim via a plain C
# compiler at first call -- found via an actual GPU inference request against this image
# during T16's Observe step (2026-09-24; not covered by an automated test):
# without gcc it failed with `RuntimeError: Failed to find C compiler`
# (triton/runtime/build.py); with gcc alone it failed compiling triton's own generated
# source with `fatal error: stdlib.h: No such file or directory`, because gcc's Recommends
# (which carries libc6-dev, the actual C standard library headers) are skipped by
# --no-install-recommends. Neither failure is exercised by the entrypoint's own CUDA
# self-test (a bare tensor add, not a real model forward pass), so both were found via the
# Observe step's real inference request, not by static review (T16 review finding #4
# follow-up). `gcc libc6-dev` (not build-essential) is the minimal set and keeps the added
# size small.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# venv, not a global pip install: sidesteps PEP 668 regardless of whether a future base
# swap reintroduces it, and keeps laya's dependency tree out of the system site-packages.
RUN python3 -m venv /opt/venv
ENV VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir "laya[serve]==${LAYA_VERSION}"

# Validates CUDA is actually usable -- not just "a CDI device got attached" -- before
# telling laya-serve/Router to use it, falling back to LAYA_DEVICE=cpu instead of
# crash-looping under `--restart always` when the driver/toolkit combination still fails
# at the first real CUDA call (T16 review finding #4; trial 1 only checked whether
# `docker run` itself failed to start, which misses a container that starts but then
# fails during CUDA init/preload).
COPY --chmod=0755 dockers/laya-entrypoint.sh /usr/local/bin/laya-entrypoint.sh

ENV HOME=/home/laya \
    HF_HOME=/home/laya/.cache/huggingface \
    HF_HUB_OFFLINE=1 \
    HF_HUB_DISABLE_TELEMETRY=1 \
    LAYA_HOST=127.0.0.1 \
    LAYA_PORT=18765 \
    LAYA_PRELOAD=1 \
    LAYA_MODELS=english

COPY --link --from=laya-fetch --chown=${USER_ID}:${GROUP_ID} /root/huggingface-baked /home/laya/.cache/huggingface

USER ${USER_ID}:${GROUP_ID}
WORKDIR /home/laya

EXPOSE 18765
# laya-serve's own GET /health route (laya/serve.py) -- cheaper than exercising a real
# POST /v1/systemone inference call on every probe.
#
# --start-period=240s: must exceed dockers/laya-entrypoint.sh's own worst case, not just
# laya-serve's typical startup. That entrypoint runs a CUDA self-test BEFORE laya-serve is
# even exec'd, bounded by LAYA_CUDA_SELFTEST_TIMEOUT (default 180s) -- a slow-but-working
# driver/toolkit can legitimately take close to that full 180s before the entrypoint falls
# back to LAYA_DEVICE=cpu and only then execs laya-serve, which itself still has to
# preload the baked checkpoint (LAYA_PRELOAD=1) before /health starts answering. 240s
# leaves a 60s margin over that 180s self-test ceiling for the actual laya-serve+preload
# startup that follows it. A start-period shorter than the self-test's own timeout would
# let normal-but-slow startups exhaust --retries and be marked unhealthy before the
# self-test has even finished picking a device.
HEALTHCHECK --interval=10s --timeout=5s --start-period=240s --retries=5 \
    CMD ["python3", "-c", "import os,urllib.request as u; u.urlopen('http://127.0.0.1:'+os.environ.get('LAYA_PORT','18765')+'/health', timeout=3)"]

ENTRYPOINT ["/usr/local/bin/laya-entrypoint.sh"]
