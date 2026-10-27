# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS go-base

ARG TARGETARCH
ENV ARCH=${TARGETARCH}
ARG USER=kpango
ARG HOME=/home/${USER}

ENV GO111MODULE=on \
    GOROOT=/usr/local/go \
    GOPATH=/go \
    GOBIN=/go/bin \
    GOARCH=${ARCH} \
    GOAMD64=v3 \
    GOOS=${OS} \
    GOPROXY="https://proxy.golang.org,direct" \
    GOFLAGS="-trimpath -ldflags=-s -buildvcs=false" \
    GOORG="golang.org" \
    GODEV="https://go.dev"
ENV PATH=${PATH}:${GOROOT}/bin:${GOBIN}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /opt
RUN --mount=type=bind,source=go.env,target=go.env,ro \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}",sharing=locked \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}",sharing=locked \
    --mount=type=cache,target="/var/cache/go-dl",id="go-dl-${TARGETARCH}",sharing=locked \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -ex \
    && BIN_NAME="go" \
    && BODY="$(curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${GODEV}/VERSION?m=text)" \
    && GO_VERSION=$(echo "${BODY}" | head -n 1) \
    && export GO_VERSION=${GO_VERSION} \
    && [ -n "${GO_VERSION}" ] || { echo "Error: VERSION is empty. curl response was: ${BODY}" >&2; exit 1; } \
    && TAR_NAME="${GO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && URL="${GODEV}/dl/${TAR_NAME}" \
    && echo ${URL} \
    && DL_PATH="/var/cache/go-dl/${TAR_NAME}" \
    && if [ ! -f "${DL_PATH}" ]; then \
           axel -n 10 -o "${DL_PATH}" "${URL}" \
           || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${DL_PATH}" "${URL}"; \
       fi \
    && tar zxf "${DL_PATH}" \
    && mv ${BIN_NAME} ${GOROOT} \
    && mkdir -p ${GOBIN} \
    && which ${BIN_NAME} \
    && ${BIN_NAME} version \
    && cp go.env "${GOROOT}/go.env"

# The `go install` below is retried up to 3 times with a linear backoff.
# proxy.golang.org intermittently drops a module fetch mid-stream (HTTP/2
# "stream error: ...; INTERNAL_ERROR; received from peer"), which go does not
# retry on its own; one such drop fails the whole image. Observed on the amd64
# `images (go)` builds of the 2026-10-07 and 2026-10-12 scheduled runs, while
# the same runs' arm64 builds and every other night passed -- a transient
# network fault, not a bad tool entry. xargs turns the inner exit 255 into its
# own exit 124, which is the code the build log reports.
FROM go-base AS go-tools
RUN --mount=type=bind,source=dockers/go.tools,target=go.tools,ro \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}",sharing=locked \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}",sharing=locked \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -ex \
    && CGO_ENABLED=0 \
       GOTOOLCHAIN=auto \
       GOEXPERIMENT=runtimesecret,simd,jsonv2 \
       xargs -P $(nproc) -n 1 \
       sh -c 'errfile=$(mktemp); n=1; until go install -trimpath -ldflags="-s -w" "$1" >/dev/null 2>"${errfile}"; do if [ "$n" -ge 3 ]; then echo "--- Failed to install $1 after ${n} attempts ---" >&2; cat "${errfile}" >&2; rm "${errfile}"; exit 255; fi; echo "--- Retrying $1 (attempt $((n + 1))/3) ---" >&2; sleep $((n * 5)); n=$((n + 1)); : > "${errfile}"; done; rm "${errfile}"' -- \
       < go.tools \
    && find ${GOPATH}/bin -type f -executable \
        | xargs -P $(nproc) -n 1 sh -c 'upx --best "$1" 2>/dev/null || true' --

# Special
FROM go-base AS dagger
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=dagger SEP=_ VER_TAG=v DEST="${GOBIN}" UPX=1

#Special
FROM go-base AS flamegraph
RUN set -x \
    && BASE="${RAWGITHUB}/brendangregg/FlameGraph/master" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${GOBIN}/flamegraph.pl"       "${BASE}/flamegraph.pl" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${GOBIN}/stackcollapse.pl"   "${BASE}/stackcollapse.pl" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${GOBIN}/stackcollapse-go.pl" "${BASE}/stackcollapse-go.pl" \
    && chmod a+x "${GOBIN}/flamegraph.pl" "${GOBIN}/stackcollapse.pl" "${GOBIN}/stackcollapse-go.pl"

#Special
FROM go-base AS fzf
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=fzf REPO='junegunn/$(APP_NAME)' OS_ARCH_SEP=_ DEST="${GOBIN}"

#Special
FROM go-base AS gh
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=gh REPO=cli/cli SEP=_ DEST="${GOBIN}" UPX=1

# Special
FROM go-base AS golangci-lint
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=golangci-lint REPO='golangci/$(APP_NAME)' DEST="${GOBIN}" UPX=1

FROM go-base AS pulumi
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=pulumi VER_TAG=v ARCH_ALIAS='$(ARCH_X64)' \
        BIN_SUBDIR='$(APP_NAME)' DEST="${GOBIN}" UPX=1

FROM go-base AS tinygo
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=tinygo REPO='tinygo-org/$(APP_NAME)' \
        BIN_SUBDIR='$(APP_NAME)/bin' DEST="${GOBIN}" UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/$(APP_NAME)$(VERSION).$(OS)-$(ARCH).tar.gz'

FROM go-base AS go-bins
COPY --link --from=dagger ${GOBIN}/dagger ${GOBIN}/dagger
COPY --link --from=flamegraph ${GOBIN}/flamegraph.pl ${GOBIN}/flamegraph.pl
COPY --link --from=flamegraph ${GOBIN}/stackcollapse-go.pl ${GOBIN}/stackcollapse-go.pl
COPY --link --from=flamegraph ${GOBIN}/stackcollapse.pl ${GOBIN}/stackcollapse.pl
COPY --link --from=fzf ${GOBIN}/fzf ${GOBIN}/fzf
COPY --link --from=gh ${GOBIN}/gh ${GOBIN}/gh
COPY --link --from=golangci-lint ${GOBIN}/golangci-lint ${GOBIN}/golangci-lint
COPY --link --from=pulumi ${GOBIN}/pulumi ${GOBIN}/pulumi
COPY --link --from=tinygo ${GOBIN}/tinygo ${GOBIN}/tinygo

FROM kpango/base:nightly AS go
ENV GOROOT=/usr/local/go \
    GOPATH=/go \
    GOBIN=/go/bin
ENV PATH=${PATH}:${GOROOT}/bin:${GOBIN}
COPY --link --from=go-base ${GOROOT} ${GOROOT}
COPY --link --from=go-tools ${GOPATH}/bin ${GOPATH}/bin
COPY --link --from=go-bins ${GOPATH}/bin ${GOPATH}/bin
