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
ENV BUN_INSTALL=/usr/local
RUN --mount=type=cache,id=bun-cache,target=/root/.bun/install/cache,sharing=locked \
    BUN_INSTALL=${BUN_INSTALL} bun install -g \
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
        @github/copilot \
        @github/copilot-language-server \
        @google/gemini-cli \
        @google/jules \
        @openai/codex \
        @qwen-code/qwen-code \
        yaml-language-server
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --break-system-packages mbake beautysh --prefix /usr

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

RUN ldconfig

WORKDIR ${HOME}
