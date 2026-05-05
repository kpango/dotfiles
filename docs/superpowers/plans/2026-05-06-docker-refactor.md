# Docker Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `env.Dockerfile` into a lean user-setup image and a separate tools image, extract cmake/vector-lib builds into `vald.Dockerfile`, and wire everything into Makefile + GitHub Actions.

**Architecture:** `base → env` (user+bun binary only) and `base → vald` (cmake+NGT/FAISS/usearch, scratch) run in parallel; `tools` (bun globals+pip+protoc+vald artifacts) builds on top of both; `dev` builds on top of `tools` plus all language runtimes.

**Tech Stack:** Docker BuildKit multi-stage, GNU Make, GitHub Actions matrix/reusable workflows.

---

### Task 1: Dead code cleanup + syntax pragma

**Files:**

- Modify: `dockers/base.Dockerfile`
- Modify: `dockers/rust.Dockerfile`
- Modify: `dockers/docker.Dockerfile`

- [ ] **Step 1: Add syntax pragma to base.Dockerfile**

Add `# syntax = docker/dockerfile:latest` as the very first line of `dockers/base.Dockerfile`:

```dockerfile
# syntax = docker/dockerfile:latest

ARG CURL_RETRY=3
```

- [ ] **Step 2: Remove unused `old` stage from rust.Dockerfile**

Delete the two lines after `FROM rust-base AS rust-stable`:

```
FROM kpango/rust:nightly AS old

```

The file should jump directly from `FROM rust-base AS rust-stable` (the stable stage) to `FROM rust-base AS cargo-asm`.

- [ ] **Step 3: Remove commented container-diff from docker.Dockerfile**

Delete lines 141–148 (the commented-out `container-diff` block):

```dockerfile
# FROM docker-base AS container-diff
# RUN set -x; cd "$(mktemp -d)" \
#     && NAME="container-diff" \
#     && REPO="jessfraz/${NAME}" \
#     && BIN_NAME=${NAME} \
#     && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${NAME}/latest/${NAME}-${OS}-${ARCH}" \
#     && chmod a+x ${BIN_PATH}/${BIN_NAME} \
#     && upx -9 ${BIN_PATH}/${BIN_NAME}
```

Also remove the corresponding commented COPY line in the final `docker` stage:

```dockerfile
# COPY --from=container-diff ${BIN_PATH}/container-diff ${DOCKER_PATH}/container-diff
```

- [ ] **Step 4: Verify with grep**

```bash
grep -n "syntax" dockers/base.Dockerfile
grep -n "AS old" dockers/rust.Dockerfile
grep -n "container-diff" dockers/docker.Dockerfile
```

Expected:

```
base.Dockerfile:1:# syntax = docker/dockerfile:latest
(no output for rust)
(no output for docker)
```

- [ ] **Step 5: Commit**

```bash
git add dockers/base.Dockerfile dockers/rust.Dockerfile dockers/docker.Dockerfile
git commit -m "chore(docker): add syntax pragma, remove dead code"
```

---

### Task 2: Create vald.Dockerfile

**Files:**

- Create: `dockers/vald.Dockerfile`

- [ ] **Step 1: Write vald.Dockerfile**

```dockerfile
# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS vald-base

ARG TARGETOS
ARG TARGETARCH

FROM vald-base AS cmake-base
WORKDIR /tmp
RUN git clone --depth 1 ${GITHUB}/vdaas/vald "/tmp/vald" \
    && cd "/tmp/vald" \
    && make cmake/install

FROM cmake-base AS ngt
WORKDIR /tmp/vald
RUN make ngt/install

FROM cmake-base AS faiss
WORKDIR /tmp/vald
RUN make faiss/install

FROM cmake-base AS usearch
WORKDIR /tmp/vald
RUN make usearch/install

FROM scratch AS vald
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV LOCAL=/usr/local
ENV BIN_PATH=${LOCAL}/bin

COPY --link --from=ngt ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --link --from=ngt ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --link --from=ngt ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
COPY --link --from=faiss ${LOCAL}/include/faiss ${LOCAL}/include/faiss
COPY --link --from=faiss ${LOCAL}/lib/libfaiss.* ${LOCAL}/lib/
COPY --link --from=usearch ${LOCAL}/include/usearch.h ${LOCAL}/include/usearch.h
COPY --link --from=usearch ${LOCAL}/lib/libusearch* ${LOCAL}/lib/
```

- [ ] **Step 2: Verify file exists and stages are correct**

```bash
grep -n "^FROM" dockers/vald.Dockerfile
```

Expected:

```
1:FROM kpango/base:nightly AS vald-base
...
FROM vald-base AS cmake-base
FROM cmake-base AS ngt
FROM cmake-base AS faiss
FROM cmake-base AS usearch
FROM scratch AS vald
```

- [ ] **Step 3: Commit**

```bash
git add dockers/vald.Dockerfile
git commit -m "feat(docker): add vald.Dockerfile for cmake/NGT/FAISS/usearch"
```

---

### Task 3: Simplify env.Dockerfile

**Files:**

- Modify: `dockers/env.Dockerfile`

Remove the `protoc`, `cmake-base`, `ngt`, `faiss`, `usearch`, `env-stage` stages and the final assembly logic. Keep only `env-base` + a minimal final `env` stage.

- [ ] **Step 1: Write the new env.Dockerfile**

Replace the entire file content with:

```dockerfile
# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS env-base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG GROUP_IDS=${GROUP_ID}

ENV LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib
ENV BASE_DIR=/home
ENV USER=${WHOAMI}
ENV HOME=${BASE_DIR}/${USER}
ENV SHELL=/usr/bin/zsh
ENV GROUP=sudo,root,users,docker,wheel
ENV UID=${USER_ID}

RUN groupadd --non-unique --gid ${GROUP_ID} docker \
    && groupadd --non-unique --gid ${GROUP_ID} wheel \
    && groupmod --non-unique --gid ${GROUP_ID} users \
    && useradd --uid ${USER_ID} \
        --gid ${GROUP_ID} \
        --non-unique --create-home \
        --shell ${SHELL} \
        --base-dir ${BASE_DIR} \
        --home ${HOME} \
        --groups ${GROUP} ${USER} \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && sed -i -e 's/# %users\tALL=(ALL)\tNOPASSWD: ALL/%users\tALL=(ALL)\tNOPASSWD: ALL/' /etc/sudoers \
    && sed -i -e 's/%users\tALL=(ALL)\tALL/# %users\tALL=(ALL)\tALL/' /etc/sudoers \
    && chown -R 0:0 /etc/sudoers.d \
    && chown -R 0:0 /etc/sudoers \
    && chmod -R 0440 /etc/sudoers.d \
    && chmod -R 0440 /etc/sudoers \
    && visudo -c

WORKDIR /tmp
RUN --mount=type=cache,target=${HOME}/.bun \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo '/lib\n\
/lib64\n\
/var/lib\n\
/usr/lib\n\
/usr/local/lib\n\
/usr/local/go/lib\n\
/usr/local/clang/lib\n\
/usr/lib/dart/lib\n\
/usr/lib/node_modules/lib\n\
/google-cloud-sdk/lib' > /etc/ld.so.conf.d/usr-local-lib.conf \
    && ldconfig \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 ${GITHUB}/soimort/translate-shell \
    && cd /tmp/translate-shell/ \
    && make TARGET=zsh -j -C /tmp/translate-shell \
    && make install -C /tmp/translate-shell \
    && cd /tmp \
    && rm -rf /tmp/translate-shell/ \
    && chown -R ${USER}:users ${HOME} \
    && chown -R ${USER}:users ${HOME}/.* \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && export BUN_INSTALL=${LOCAL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL https://bun.sh/install \
        | bash

FROM env-base AS env
WORKDIR ${HOME}
```

- [ ] **Step 2: Verify only env-base and env stages remain**

```bash
grep -n "^FROM" dockers/env.Dockerfile
```

Expected:

```
2:FROM kpango/base:nightly AS env-base
...
FROM env-base AS env
```

- [ ] **Step 3: Verify removed stages are gone**

```bash
grep -n "protoc\|cmake\|ngt\|faiss\|usearch\|env-stage\|bun install -g" dockers/env.Dockerfile
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add dockers/env.Dockerfile
git commit -m "refactor(docker): slim env.Dockerfile to user-setup + bun binary only"
```

---

### Task 4: Create tools.Dockerfile

**Files:**

- Create: `dockers/tools.Dockerfile`

This file takes `kpango/env:nightly` as base, adds protoc (moved from env), bun global packages + pip (moved from env-stage), then assembles with vald artifacts.

- [ ] **Step 1: Write tools.Dockerfile**

```dockerfile
# syntax = docker/dockerfile:latest
FROM kpango/env:nightly AS tools-base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
ARG USER_ID=1000
ARG GROUP_ID=1000

FROM kpango/vald:nightly AS vald-src

FROM tools-base AS protoc
WORKDIR /tmp
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && REPO_NAME="protobuf" \
    && BIN_NAME="protoc" \
    && REPO="protocolbuffers/${REPO_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; arm64) ARCH="aarch_64" ;; esac \
    && ZIP_NAME="${BIN_NAME}-${VERSION}-${OS}-${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "/tmp/${BIN_NAME}.zip" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ZIP_NAME}.zip" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local "bin/${BIN_NAME}" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local 'include/*' \
    && rm -f /tmp/protoc.zip \
    && rm -rf /tmp/*

FROM tools-base AS tools-stage
WORKDIR /tmp
ENV PATH=${LOCAL}/bin:${PATH}
ENV BUN_INSTALL=/usr/local
RUN --mount=type=cache,target=/root/.bun/install/cache \
    BUN_INSTALL=${BUN_INSTALL} bun install -g \
        bash-language-server \
        dockerfile-language-server-nodejs \
        markdownlint-cli \
        n \
        opencode-ai \
        prettier \
        pyright \
        typescript \
        typescript-language-server \
        @anthropic-ai/claude-code \
        @byterover/cipher \
        @colbymchenry/codegraph \
        @github/copilot \
        @github/copilot-language-server \
        @google/gemini-cli \
        @google/jules \
        @openai/codex \
        @qwen-code/qwen-code \
        yaml-language-server \
    && ${BUN_INSTALL}/bin/n latest
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install mbake beautysh --prefix /usr

FROM tools-stage AS tools
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

COPY --link --from=vald-src ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --link --from=vald-src ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --link --from=vald-src ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
COPY --link --from=vald-src ${LOCAL}/include/faiss ${LOCAL}/include/faiss
COPY --link --from=vald-src ${LOCAL}/lib/libfaiss.* ${LOCAL}/lib/
COPY --link --from=vald-src ${LOCAL}/include/usearch.h ${LOCAL}/include/usearch.h
COPY --link --from=vald-src ${LOCAL}/lib/libusearch* ${LOCAL}/lib/
COPY --link --from=protoc ${BIN_PATH}/protoc ${BIN_PATH}/protoc
COPY --link --from=protoc ${LOCAL}/include/google/protobuf ${LOCAL}/include/google/protobuf

RUN ldconfig \
    && rm -rf /tmp/* /var/cache

WORKDIR ${HOME}
```

- [ ] **Step 2: Verify FROM chain**

```bash
grep -n "^FROM" dockers/tools.Dockerfile
```

Expected:

```
2:FROM kpango/env:nightly AS tools-base
...
FROM kpango/vald:nightly AS vald-src
FROM tools-base AS protoc
FROM tools-base AS tools-stage
FROM tools-stage AS tools
```

- [ ] **Step 3: Commit**

```bash
git add dockers/tools.Dockerfile
git commit -m "feat(docker): add tools.Dockerfile (bun globals + pip + protoc + vald)"
```

---

### Task 5: Update dev.Dockerfile

**Files:**

- Modify: `dockers/dev.Dockerfile`

Change the base from `kpango/env:nightly` to `kpango/tools:nightly`.

- [ ] **Step 1: Add tools import and replace base**

In `dockers/dev.Dockerfile`, replace:

```dockerfile
FROM kpango/env:nightly AS env

FROM env
```

with:

```dockerfile
FROM kpango/tools:nightly AS tools

FROM tools
```

- [ ] **Step 2: Verify**

```bash
grep -n "kpango/env\|kpango/tools\|^FROM env\|^FROM tools" dockers/dev.Dockerfile
```

Expected:

```
19:FROM kpango/tools:nightly AS tools
21:FROM tools
```

No `kpango/env` references should remain.

- [ ] **Step 3: Commit**

```bash
git add dockers/dev.Dockerfile
git commit -m "refactor(docker): dev.Dockerfile base → kpango/tools:nightly"
```

---

### Task 6: Update Makefile.d/docker.mk

**Files:**

- Modify: `Makefile.d/docker.mk`

Add `zig` and `nix` and `vald` to the parallel xpanes list; add `build_tools` as a sequential step after xpanes in both `build` and `prod`.

- [ ] **Step 1: Update build target**

Replace:

```makefile
build: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx \
	build_base
	@xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) -f $(ROOTDIR)/Makefile build_{}" go docker rust dart k8s nim gcloud env
```

with:

```makefile
build: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx \
	build_base
	@xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) -f $(ROOTDIR)/Makefile build_{}" go docker rust dart k8s nim gcloud zig nix env vald
	@$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) build_tools
```

- [ ] **Step 2: Update prod target**

Replace:

```makefile
prod: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx \
	build_base
	@xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=\"--no-cache\" -f $(ROOTDIR)/Makefile build_{}" go docker rust dart k8s nim gcloud env
	@$(MAKE) DOCKER_EXTRA_OPTS="--no-cache" prod_build
```

with:

```makefile
prod: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx \
	build_base
	@xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=\"--no-cache\" -f $(ROOTDIR)/Makefile build_{}" go docker rust dart k8s nim gcloud zig nix env vald
	@$(MAKE) DOCKER_EXTRA_OPTS="--no-cache" build_tools
	@$(MAKE) DOCKER_EXTRA_OPTS="--no-cache" prod_build
```

- [ ] **Step 3: Verify**

```bash
grep -n "zig\|nix\|tools\|vald" Makefile.d/docker.mk
```

Expected output includes lines showing `zig nix env vald` in xpanes and `build_tools` as a step.

- [ ] **Step 4: Commit**

```bash
git add Makefile.d/docker.mk
git commit -m "fix(make): add zig/nix/vald to parallel builds; add tools step"
```

---

### Task 7: Update .github/workflows/docker-matrix.yaml

**Files:**

- Modify: `.github/workflows/docker-matrix.yaml`

Add `vald` to the images matrix; add `tools` job after images; update `dev` dependencies.

- [ ] **Step 1: Add vald to matrix and add tools job**

Replace the entire file content:

```yaml
name: "Build docker images"
on:
  push:
    branches:
      - main
    tags:
      - "*.*.*"
      - "v*.*.*"
      - "*.*.*-*"
      - "v*.*.*-*"
    paths:
      - "dockers/**"
      - "Makefile"
      - ".github/workflows/**"
  pull_request:
    paths:
      - "dockers/**"
      - "Makefile"
      - ".github/workflows/**"
  workflow_dispatch:
  schedule:
    - cron: "0 23 * * *"

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  base:
    uses: ./.github/workflows/docker-reusable.yaml
    with:
      image_name: base
    secrets: inherit

  images:
    needs: base
    strategy:
      fail-fast: false
      matrix:
        image: [dart, docker, env, gcloud, go, k8s, nim, nix, rust, vald, zig]
    uses: ./.github/workflows/docker-reusable.yaml
    with:
      image_name: ${{ matrix.image }}
    secrets: inherit

  tools:
    needs: [base, images]
    uses: ./.github/workflows/docker-reusable.yaml
    with:
      image_name: tools
    secrets: inherit

  dev:
    needs: [base, images, tools]
    if: |
      always() &&
      needs.base.result == 'success' &&
      needs.tools.result == 'success' &&
      !cancelled()
    uses: ./.github/workflows/docker-reusable.yaml
    with:
      image_name: dev
    secrets: inherit
```

- [ ] **Step 2: Verify jobs and dependencies**

```bash
grep -n "image:\|needs:\|tools\|vald" .github/workflows/docker-matrix.yaml
```

Expected output shows `vald` in matrix list, `tools` job with `needs: [base, images]`, and `dev` with `needs: [base, images, tools]`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/docker-matrix.yaml
git commit -m "ci: add vald to matrix; add tools job; update dev dependencies"
```

---

### Task 8: Update .github/actions/docker/action.yaml

**Files:**

- Modify: `.github/actions/docker/action.yaml`

Add `tools` and `vald` to the free-disk-space condition and the GC flag condition.

- [ ] **Step 1: Extend free-disk-space condition**

Replace:

```yaml
- name: Free Disk Space (Ubuntu)
  if: ${{ inputs.image_name == 'go' || inputs.image_name == 'rust' || inputs.image_name == 'env' || inputs.image_name == 'nix' }}
```

with:

```yaml
- name: Free Disk Space (Ubuntu)
  if: ${{ inputs.image_name == 'go' || inputs.image_name == 'rust' || inputs.image_name == 'env' || inputs.image_name == 'nix' || inputs.image_name == 'tools' || inputs.image_name == 'vald' }}
```

Note: this line is in `docker-reusable.yaml`, not `action.yaml`. Check both files.

- [ ] **Step 2: Extend GC_FLAG condition in action.yaml**

Replace:

```bash
        if [[ "$IMAGE_NAME" == "go" || "$IMAGE_NAME" == "rust" || "$IMAGE_NAME" == "env" ]]; then
```

with:

```bash
        if [[ "$IMAGE_NAME" == "go" || "$IMAGE_NAME" == "rust" || "$IMAGE_NAME" == "env" || "$IMAGE_NAME" == "tools" || "$IMAGE_NAME" == "vald" ]]; then
```

- [ ] **Step 3: Verify**

```bash
grep -n "tools\|vald" .github/actions/docker/action.yaml .github/workflows/docker-reusable.yaml
```

Expected: both `tools` and `vald` appear in the condition lines.

- [ ] **Step 4: Commit**

```bash
git add .github/actions/docker/action.yaml .github/workflows/docker-reusable.yaml
git commit -m "ci: add tools/vald to disk-cleanup and GC conditions"
```

---

### Task 9: Final verification

- [ ] **Step 1: Confirm new Dockerfiles exist**

```bash
ls dockers/*.Dockerfile | sort
```

Expected:

```
dockers/base.Dockerfile
dockers/dart.Dockerfile
dockers/dev.Dockerfile
dockers/docker.Dockerfile
dockers/env.Dockerfile
dockers/gcloud.Dockerfile
dockers/go.Dockerfile
dockers/k8s.Dockerfile
dockers/nim.Dockerfile
dockers/nix.Dockerfile
dockers/rust.Dockerfile
dockers/tools.Dockerfile
dockers/vald.Dockerfile
dockers/zig.Dockerfile
```

- [ ] **Step 2: Confirm no cmake/ngt/faiss/usearch/bun-globals remain in env.Dockerfile**

```bash
grep -c "cmake\|ngt\|faiss\|usearch\|bun install -g\|env-stage\|protoc" dockers/env.Dockerfile
```

Expected: `0`

- [ ] **Step 3: Confirm dev.Dockerfile references tools not env**

```bash
grep "kpango/env\|kpango/tools" dockers/dev.Dockerfile
```

Expected: only `kpango/tools:nightly`

- [ ] **Step 4: Confirm Makefile has zig/nix/vald/tools**

```bash
grep "zig\|nix\|vald\|build_tools" Makefile.d/docker.mk
```

Expected: appears in both `build` and `prod` targets.

- [ ] **Step 5: Confirm GitHub Actions has tools job and vald in matrix**

```bash
grep -n "tools\|vald" .github/workflows/docker-matrix.yaml
```

Expected: `vald` in matrix, `tools` as standalone job.
