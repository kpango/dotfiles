# syntax = docker/dockerfile:latest

FROM kpango/base:nightly AS zig-base

ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

ENV ZIG_HOME=/usr/local/zig
ENV PATH=${ZIG_HOME}:${PATH}

WORKDIR /opt
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# zig-compiler — download and unpack the latest stable Zig SDK.
# ziglang.org/download/index.json lists all versions; we pick the latest
# non-master key and fetch its tarball URL directly from the manifest.
FROM zig-base AS zig-compiler
RUN set -ex \
    && case "${ARCH}" in \
         amd64) ZIG_ARCH="${XARCH}" ;; \
         arm64) ZIG_ARCH="${AARCH}" ;; \
         *) echo "Unsupported arch: ${ARCH}" >&2 && exit 1 ;; \
       esac \
    && BODY=$(curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL https://ziglang.org/download/index.json) \
    && VERSION=$(printf '%s' "${BODY}" | jq -r '[keys[] | select(. != "master")] | sort_by(split(".") | map(tonumber)) | last') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { echo "Error: VERSION is empty or null. Response: ${BODY}" >&2; exit 1; } \
    && URL=$(printf '%s' "${BODY}" | jq -r ".\"${VERSION}\".\"${ZIG_ARCH}-linux\".tarball") \
    && [ -n "${URL}" ] && [ "${URL}" != "null" ] \
        || { echo "Error: tarball URL not found for ${ZIG_ARCH}-linux ${VERSION}" >&2; exit 1; } \
    && TAR_FILE="$(basename "${URL}")" \
    && echo "${URL}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL}" \
    && tar -xJf "${TAR_FILE}" \
    && rm "${TAR_FILE}" \
    && mv "${TAR_FILE%.tar.xz}" "${ZIG_HOME}" \
    && "${ZIG_HOME}/zig" version

# zls — Zig Language Server, downloaded from GitHub releases.
FROM zig-base AS zls
RUN --mount=type=secret,id=gat \
    set -ex \
    && case "${ARCH}" in \
         amd64) ZIG_ARCH="${XARCH}" ;; \
         arm64) ZIG_ARCH="${AARCH}" ;; \
         *) echo "Unsupported arch: ${ARCH}" >&2 && exit 1 ;; \
       esac \
    && BIN_NAME="zls" \
    && REPO="zigtools/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; exit 1; } \
    && ASSET_URL=$(echo "${BODY}" | jq -r \
         ".assets[] | select(.name | test(\"${ZIG_ARCH}.*linux.*\\\\.tar\\\\.xz$\"; \"i\")) | .browser_download_url" \
         | head -1) \
    && [ -n "${ASSET_URL}" ] \
        || { echo "Error: no tarball asset found for ${ZIG_ARCH}-linux v${VERSION}" >&2; exit 1; } \
    && TAR_FILE="zls-${ZIG_ARCH}-linux.tar.xz" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${TAR_FILE}" "${ASSET_URL}" \
    && tar -xJf "${TAR_FILE}" \
    && rm "${TAR_FILE}" \
    && install -m 755 "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx --best "${BIN_PATH}/${BIN_NAME}" || true \
    && "${BIN_PATH}/${BIN_NAME}" --version

# zig — final scratch image: compiler SDK + language server.
FROM scratch AS zig

ENV ZIG_HOME=/usr/local/zig
ENV BIN_PATH=/usr/local/bin
ENV PATH=${ZIG_HOME}:${BIN_PATH}:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

COPY --link --from=zig-compiler ${ZIG_HOME} ${ZIG_HOME}
COPY --link --from=zls          ${BIN_PATH}/zls ${BIN_PATH}/zls
