# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS go-base

ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG USER=kpango
ARG HOME=/home/${USER}

ENV GO111MODULE=on
ENV GOROOT=/usr/local/go
ENV GOPATH=/go
ENV GOBIN=${GOPATH}/bin
ENV GOARCH=${ARCH}
ENV GOOS=${OS}
ENV GOPROXY="https://proxy.golang.org,direct"
ENV GOFLAGS="-ldflags=-w -ldflags=-s"
ENV GOORG="golang.org"
ENV GODEV="https://go.dev"
ENV GITHUBCOM=github.com
ENV API_GITHUB=https://api.${GITHUBCOM}/repos
ENV GITHUB=https://${GITHUBCOM}
ENV PATH=${PATH}:${GOROOT}/bin:${GOBIN}
ENV RELEASE_DL=releases/download
ENV RELEASE_LATEST=releases/latest
ENV GO_FLAGS="-trimpath -modcacherw -a -tags netgo"

WORKDIR /tmp
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN echo "BUILDPLATFORM: ${BUILDPLATFORM} → TARGETPLATFORM: ${TARGETPLATFORM}" \
    && if [ "${ARCH}" = "amd64" ] ; then  \
         export CC=${XARCH}-${OS}-gnu-gcc; \
         export CC_FOR_TARGET=${CC}; \
       elif [ "${ARCH}" = "arm64" ] ; then  \
         export CC=${AARCH}-${OS}-gnu-gcc; \
         export CC_FOR_TARGET=${CC}; \
       fi

WORKDIR /opt
RUN --mount=type=bind,source=go.env,target=go.env,ro \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}",sharing=locked \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}",sharing=locked \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -ex \
    && BIN_NAME="go" \
    && BODY="$(curl -fsSL ${GODEV}/VERSION?m=text)" \
    && GO_VERSION=$(echo "${BODY}" | head -n 1) \
    && export GO_VERSION=${GO_VERSION} \
    && [ -n "${GO_VERSION}" ] || { echo "Error: VERSION is empty. curl response was: ${BODY}" >&2; exit 1; } \
    && TAR_NAME="${GO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && curl -fsSLO "${GODEV}/dl/${TAR_NAME}" \
    && tar zxf "${TAR_NAME}" \
    && rm "${TAR_NAME}" \
    && mv ${BIN_NAME} ${GOROOT} \
    && mkdir -p ${GOBIN} \
    && which ${BIN_NAME} \
    && ${BIN_NAME} version \
    && cp go.env "${GOROOT}/go.env"

FROM go-base AS go-tools
RUN --mount=type=bind,source=dockers/go.tools,target=go.tools,ro \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}",sharing=locked \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}",sharing=locked \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -ex \
    && cat go.tools | \
        CGO_ENABLED=0 \
        GOTOOLCHAIN=${GO_VERSION} \
        xargs -P 64 -I {} \
        sh -c 'errfile=$(mktemp); if ! go install {} >/dev/null 2>"${errfile}"; then echo "--- Failed to install {} ---" >&2; cat "${errfile}" >&2; rm "${errfile}"; exit 255; fi; rm "${errfile}"'

# Special
FROM go-base AS dagger
RUN set -x && cd "$(mktemp -d)" \
    && BIN_NAME="dagger" \
    && curl -fsSL https://dl.${BIN_NAME}.io/${BIN_NAME}/install.sh | BIN_DIR=${GOBIN} sh \
    && upx -9 ${GOBIN}/${BIN_NAME}

#Special
FROM go-base AS flamegraph
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="FlameGraph" \
    && REPO="brendangregg/${BIN_NAME}" \
    && TMPDIR="/tmp/${BIN_NAME}" \
    && git clone --depth 1 \
        "${GITHUB}/${REPO}" \
        "${TMPDIR}" \
    && chmod -R a+x "${TMPDIR}" \
    && cp ${TMPDIR}/flamegraph.pl ${GOBIN}/ \
    && cp ${TMPDIR}/stackcollapse.pl ${GOBIN}/ \
    && cp ${TMPDIR}/stackcollapse-go.pl ${GOBIN}/

#Special
FROM go-base AS fzf
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="fzf" \
    && REPO="junegunn/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH)" \
    && TAR_NAME="${BIN_NAME}-${VERSION}-${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv ${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

#Special
FROM go-base AS gh
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gh" \
    && REPO="cli/cli" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH)" \
    && TAR_NAME="${BIN_NAME}_${VERSION}_${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${TAR_NAME}/bin/${BIN_NAME}" "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

# Special
FROM go-base AS golangci-lint
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="golangci-lint" \
    && REPO="golangci/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH)" \
    && TAR_NAME="${BIN_NAME}-${VERSION}-${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv ${TAR_NAME}/${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM go-base AS pulumi
RUN set -x && cd "$(mktemp -d)" \
    && BIN_NAME="pulumi" \
    && curl -fsSL https://get.${BIN_NAME}.com | sh \
    && mv ${HOME}/.${BIN_NAME}/bin/${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM go-base AS tinygo
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-pkg-${TARGETARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${TARGETARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="tinygo" \
    && REPO="${BIN_NAME}-org/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH)" \
    && TAR_NAME="${BIN_NAME}${VERSION}.${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv ${BIN_NAME}/bin/${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM go-base AS go
RUN find ${GOROOT}/bin -type f -executable | xargs -P $(nproc) -n 1 upx -9

FROM go-tools AS tools
RUN find ${GOPATH}/bin -type f -executable | xargs -P $(nproc) -n 1 upx -9

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

FROM scratch
ENV GOROOT=/usr/local/go
ENV GOPATH=/go
COPY --link --from=go ${GOROOT} ${GOROOT}
COPY --link --from=go-bins ${GOPATH}/bin ${GOPATH}/bin
COPY --link --from=tools ${GOPATH}/bin ${GOPATH}/bin
