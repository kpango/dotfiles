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
ENV BUN_INSTALL=/usr/local
RUN --mount=type=cache,id=bun-cache-${TARGETARCH},target=/root/.bun/install/cache,sharing=locked \
    BUN_INSTALL=${BUN_INSTALL} bun install -g \
        bash-language-server \
        dockerfile-language-server-nodejs \
        hunkdiff \
        markdownlint-cli \
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
        yaml-language-server
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --break-system-packages \
        mbake \
        beautysh \
        graphifyy \
        --prefix /usr/local

# --- Antigravity CLI Layer ---
FROM --platform=$BUILDPLATFORM tools-base AS agy-fetcher
ARG TARGETARCH
ARG BIN_PATH=/usr/local/bin
USER root
RUN mkdir -p ${BIN_PATH} && \
    curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/install.sh && \
    bash /tmp/install.sh --dir ${BIN_PATH}

FROM tools-stage AS tools
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

# --- Antigravity CLI Layer ---
COPY --link --from=agy-fetcher ${BIN_PATH}/agy ${BIN_PATH}/agy
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
