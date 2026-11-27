---
title: "Docker build expands $$ to the shell, so resolve per-arch asset names in make"
author: Kpango
date: 2026-11-21
branch: main
id: l-c187cf9e
scope: repo
status: active
src: agent
touches:
  - dockers/dev.Dockerfile
  - dockers/tools.Dockerfile
  - Makefile.d/download.mk
---

## Decided

`dockers/tools.Dockerfile` now resolves hadolint's arch alias inside make
(`URL_TEMPLATE='...hadolint-$(OS_ALIAS)-$(subst amd64,x86_64,$(ARCH))'`) instead of a
shell variable. Under `# syntax = docker/dockerfile:latest`, `$$` reaches the shell
untouched, so `$$hadolint_arch` became bash's `$$` (PID 1) and the download probed
`hadolint-linux-1hadolint_arch` (HTTP 404) during the image build.

## Tried and ruled out

- `ARCH_ALIAS="$$hadolint_arch"` + `URL_TEMPLATE="...-$$hadolint_arch"`: a local
  `make -f Makefile.d/download.mk install-tool` test passed because the template was
  passed as a literal string; only `docker buildx build --target tools-stage` exposed
  the failure.
- `$${hadolint_arch}` is not a workaround: it rendered as `1{hadolint_arch}`, so `$$`
  is not a dollar escape in this frontend (a minimal Dockerfile confirmed A/B/C/D).

## Watch out

- Verify Dockerfile download steps with a real `--target` build; make-level tests do
  not exercise the Dockerfile expansion layer.
- `$var` is still expanded by the shell, so keep `\$(GITHUB)`-style escapes when a
  `$(...)` expression must reach make.
