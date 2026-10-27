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
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=protoc REPO=protocolbuffers/protobuf EXT=.zip \
        ARCH_ALIAS='$(XARCH_PROTOC)' BIN_SUBDIR=bin \
        EXTRA_GLOB=include

FROM tools-base AS tools-stage
WORKDIR /tmp
ARG CURL_RETRY=5
ARG CURL_RETRY_DELAY=2
ENV CFLAGS="-O3 -DNDEBUG -pipe -fno-ident -fomit-frame-pointer -fno-semantic-interposition -fno-plt -fdata-sections -ffunction-sections -fno-math-errno -fno-trapping-math" \
    CXXFLAGS="-O3 -DNDEBUG -std=c++23 -pipe -fno-ident -fomit-frame-pointer -fno-semantic-interposition -fvisibility-inlines-hidden -fno-plt -fdata-sections -ffunction-sections -fno-math-errno -fno-trapping-math" \
    LDFLAGS="-fuse-ld=lld -Wl,-O3 -Wl,--as-needed -Wl,--gc-sections -Wl,--hash-style=gnu -Wl,-z,now"
# pip runs ahead of the bun layer on purpose: its inputs change only when this
# file does, so keeping it above the TOOLS_REFRESH-busted layer below leaves it
# a cache hit on every rebuild instead of being invalidated along with it.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --break-system-packages \
        mbake \
        beautysh \
        --prefix /usr/local

# Node.js 24's V8 headers require C++20 or later for native addons (e.g. tree-sitter bindings); we compile with C++23.
# Pre-installing node-gyp globally ensures native compilation has a reliable node-gyp
# with all internal modules intact, avoiding flawed ad-hoc extraction via bunx.
RUN --mount=type=cache,target=/root/.npm \
    npm install -g node-gyp

# TOOLS_REFRESH is a cache-bust token (Makefile.d/docker.mk passes the UTC date
# as YYYYMMDD; `docker/build/tools` is the only caller that sets it). Every
# entry below is unpinned, so `bun install -g` resolves each to its current
# `latest` -- but a RUN whose command never changes stays a cache hit forever,
# which silently freezes the image on whatever was latest the day the layer was
# first built. Referencing the ARG inside the command is what moves the cache
# key: per Docker's "Impact on build caching", an ARG causes a cache miss at its
# first *usage*, not at its definition.
ARG TOOLS_REFRESH=0
ENV BUN_INSTALL=/usr/local
RUN --mount=type=cache,id=bun-cache-${TARGETARCH},target=/root/.bun/install/cache,sharing=locked \
    echo "tools refresh token: ${TOOLS_REFRESH}" && \
    CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" LDFLAGS="${LDFLAGS}" BUN_INSTALL=${BUN_INSTALL} bun install -g \
        bash-language-server \
        dockerfile-language-server-nodejs \
        markdownlint-cli \
        opencode-ai \
        prettier \
        pyright \
        typescript \
        typescript-language-server \
        @anthropic-ai/claude-code \
        @byterover/cipher \
        @colbymchenry/codegraph \
        @earendil-works/pi-coding-agent \
        @github/copilot \
        @github/copilot-language-server \
        @google/jules \
        @nanonets/graft \
        @openai/codex \
        @qwen-code/qwen-code \
        yaml-language-server

# --- Antigravity CLI Layer ---
FROM --platform=$BUILDPLATFORM tools-base AS agy-fetcher
ARG TARGETARCH
ARG BIN_PATH=/usr/local/bin
ARG TOOLS_REFRESH=0
USER root
# --compressed is required, not cosmetic: antigravity.google intermittently
# answers with a gzip body and a Content-Encoding: gzip header even though no
# Accept-Encoding was offered, and curl only decodes an encoding it asked for.
# Without it the saved file is raw gzip, `bash install.sh` reports "cannot
# execute binary file" and exits 126. That is the exact error in the `tools`
# build logs of the 2026-10-11 (amd64) and 2026-10-12 (arm64) scheduled runs,
# and since `tools/merge` needs both arches to pass, every one of the three
# scheduled runs on 2026-10-10/11/12 skipped merge -- so `tools:nightly` has not
# been republished since 2026-10-09. The failing arch alternates between the two
# runs, which is what makes this an intermittent CDN behaviour rather than an
# arch-specific one. Reproduced directly against the live URL on 2026-10-14:
# one gzip response, then three plain ones, from the same four-request loop.
RUN mkdir -p ${BIN_PATH} && \
    echo "tools refresh token: ${TOOLS_REFRESH}" && \
    curl -fsSL --compressed https://antigravity.google/cli/install.sh -o /tmp/install.sh && \
    bash /tmp/install.sh --dir ${BIN_PATH}

# --- Prime Agent Layer ---
# PrimeIntellect-ai/prime-agent ships no npm package and is absent from both
# nixpkgs and the AUR (all three checked 2026-10-14), so the official installer
# is the only distribution channel; it verifies the release tarball against the
# published SHA256SUMS before installing. Unlike agy-fetcher this stage stays on
# TARGETPLATFORM so the installer's own `uname -m` detection picks the right
# release artifact. ~/.prime/agent -- where primeagent/install puts this repo's
# config -- is documented as never touched by the installer.
FROM tools-base AS prime-fetcher
ARG TARGETARCH
ARG TOOLS_REFRESH=0
USER root
RUN echo "tools refresh token: ${TOOLS_REFRESH}" && \
    curl -fsSL --compressed https://app.primeintellect.ai/prime-agent/install.sh \
        -o /tmp/prime-install.sh && \
    PRIME_AGENT_RUST_PREFIX=${LOCAL} PRIME_AGENT_UV_BIN_DIR=${BIN_PATH} \
        sh /tmp/prime-install.sh

FROM tools-stage AS tools
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

# --- Antigravity CLI Layer ---
COPY --link --from=agy-fetcher ${BIN_PATH}/agy ${BIN_PATH}/agy

# --- Prime Agent Layer ---
COPY --link --from=prime-fetcher ${BIN_PATH}/prime-agent ${BIN_PATH}/prime-agent
COPY --link --from=prime-fetcher ${LOCAL}/share/prime-agent ${LOCAL}/share/prime-agent
COPY --link --from=vald-src ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --link --from=vald-src ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --link --from=vald-src ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
COPY --link --from=vald-src ${LOCAL}/include/faiss ${LOCAL}/include/faiss
COPY --link --from=vald-src ${LOCAL}/lib/libfaiss.* ${LOCAL}/lib/
COPY --link --from=vald-src ${LOCAL}/include/usearch.h ${LOCAL}/include/usearch.h
COPY --link --from=vald-src ${LOCAL}/lib/libusearch* ${LOCAL}/lib/
COPY --link --from=protoc ${BIN_PATH}/protoc ${BIN_PATH}/protoc
COPY --link --from=protoc ${LOCAL}/include/google/protobuf ${LOCAL}/include/google/protobuf

RUN ldconfig

WORKDIR ${HOME}
