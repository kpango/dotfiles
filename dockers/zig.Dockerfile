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
RUN --mount=type=cache,id=zig-download-${ARCH},target=/tmp/zig-cache \
    set -ex \
    && case "${ARCH}" in \
         amd64) ZIG_ARCH="x86_64" ;; \
         arm64) ZIG_ARCH="aarch64" ;; \
         *) echo "Unsupported arch: ${ARCH}" >&2 && exit 1 ;; \
       esac \
    && BODY=$(curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL https://ziglang.org/download/index.json) \
    && URL="" VERSION="" \
    && for ver in $(printf '%s' "${BODY}" | jq -r '[keys[] | select(. != "master") | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | sort_by(split(".") | map(tonumber)) | reverse | .[]'); do \
         u=$(printf '%s' "${BODY}" | jq -r ".\"${ver}\".\"${ZIG_ARCH}-linux\".tarball // empty"); \
         [ -n "${u}" ] || continue; \
         if curl --max-time 10 --retry 0 -fsSL -r "0-1023" "${u}" -o /dev/null 2>/dev/null; then VERSION="${ver}"; URL="${u}"; break; fi; \
       done \
    && [ -n "${VERSION}" ] && [ "${VERSION}" != "null" ] \
        || { echo "Error: no working Zig release found" >&2; exit 1; } \
    && TAR_FILE="$(basename "${URL}")" \
    && echo "${URL}" \
    && _retry=0 \
    && until axel -n 10 -o "/tmp/zig-cache/${TAR_FILE}" "${URL}"; do \
           _retry=$((_retry + 1)); \
           [ "${_retry}" -le "${CURL_RETRY}" ] \
               || { echo "Download failed after ${CURL_RETRY} retries" >&2; exit 1; }; \
           sleep "${CURL_RETRY_DELAY}"; \
       done \
    && tar -xJf "/tmp/zig-cache/${TAR_FILE}" \
    && rm "/tmp/zig-cache/${TAR_FILE}" \
    && mv "${TAR_FILE%.tar.xz}" "${ZIG_HOME}" \
    && "${ZIG_HOME}/zig" version

# zls — Zig Language Server, downloaded from GitHub releases.
FROM zig-base AS zls
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    set -ex && \
    XARCH=$(case "${ARCH}" in amd64) echo "x86_64" ;; arm64) echo "aarch64" ;; *) echo "x86_64" ;; esac) && \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=zls REPO='zigtools/$(APP_NAME)' \
        EXT=.tar.xz UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/$(VERSION)/$(APP_NAME)-'"${XARCH}"'-linux.tar.xz' \
    && "${BIN_PATH}/zls" --version

# zig — final scratch image: compiler SDK + language server.
FROM scratch AS zig

ENV ZIG_HOME=/usr/local/zig
ENV BIN_PATH=/usr/local/bin
ENV PATH=${ZIG_HOME}:${BIN_PATH}:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

COPY --link --from=zig-compiler ${ZIG_HOME} ${ZIG_HOME}
COPY --link --from=zls          ${BIN_PATH}/zls ${BIN_PATH}/zls
