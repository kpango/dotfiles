# syntax = docker/dockerfile:latest
FROM kpango/base:latest AS go-base

ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG USER=kpango
ARG HOME=/home/${USER}

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV AARCH=aarch_64
ENV XARCH=x86_64

ENV GO111MODULE=on
ENV DEBIAN_FRONTEND=noninteractive
ENV INITRD=No
ENV LANG=en_US.UTF-8
ENV GOROOT=/usr/local/go
ENV GOPATH=/go
ENV GOBIN=${GOPATH}/bin
ENV GOARCH=${ARCH}
ENV GOOS=${OS}
ENV GOPROXY="https://proxy.golang.org,https://goproxy.io,direct"
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

RUN echo "BUILDPLATFORM: $BUILDPLATFORM → TARGETPLATFORM: $TARGETPLATFORM" \
    && apt update -y \
    && apt upgrade -y \
    && if [ "${ARCH}" = "amd64" ] ; then  \
         apt install -y --no-install-recommends --fix-missing gcc-${XARCH}-${OS}-gnu; \
         export CC=${XARCH}-${OS}-gnu-gcc; \
         export CC_FOR_TARGET=${CC}; \
       elif [ "${ARCH}" = "arm64" ] ; then  \
         apt install -y --no-install-recommends --fix-missing gcc-${AARCH}-${OS}-gnu; \
         export CC=${AARCH}-${OS}-gnu-gcc; \
         export CC_FOR_TARGET=${CC}; \
       fi

WORKDIR /opt
RUN set -x && cd "$(mktemp -d)" \
    && BIN_NAME="go" \
    && BODY="$(curl -fsSL ${GODEV}/VERSION?m=text)" \
    && GO_VERSION=$(echo "$BODY" | head -n 1) \
    && export GO_VERSION=${GO_VERSION} \
    && [ -n "${GO_VERSION}" ] || { echo "Error: VERSION is empty. curl response was: ${BODY}" >&2; exit 1; } \
    && TAR_NAME="${GO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && curl -fsSLO "${GODEV}/dl/${TAR_NAME}" \
    && tar zxf "${TAR_NAME}" \
    && rm "${TAR_NAME}" \
    && mv ${BIN_NAME} ${GOROOT} \
    && mkdir -p ${GOBIN} \
    && which ${BIN_NAME} \
    && ${BIN_NAME} version
COPY go.env "${GOROOT}/go.env"

FROM go-base AS go-tools
WORKDIR ${GOPATH}/src/kpango.com/dotfiles/mod
COPY dockers/go.tools "${GOPATH}/src/kpango.com/dotfiles/mod/go.tools"
RUN set -ex \
    && cat go.tools | \
        CGO_ENABLED=0 \
        GOTOOLCHAIN=${GO_VERSION} \
        xargs -P 64 -I {} \
        sh -c 'go install {} > /dev/null || (echo "Failed to install {}" && exit 255)'

# Special
FROM go-base AS dagger
RUN set -x && cd "$(mktemp -d)" \
    && BIN_NAME="dagger" \
    && curl -fsSL https://dl.${BIN_NAME}.io/${BIN_NAME}/install.sh | BIN_DIR=${GOBIN} sh \
    && upx -9 ${GOBIN}/${BIN_NAME}

#Special
FROM go-base AS flamegraph
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
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
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="fzf" \
    && REPO="junegunn/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
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
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gh" \
    && REPO="cli/cli" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
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
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="golangci-lint" \
    && REPO="golangci/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH)" \
    && TAR_NAME="${BIN_NAME}-${VERSION}-${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv ${TAR_NAME}/${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM go-base AS gopls
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gopls" \
    && REPO="${GOORG}/x/tools" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${REPO}/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM go-base AS guru
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="guru" \
    && REPO="${GOORG}/x/tools" \
    && go install \
    ${GO_FLAGS} \
    "${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"


FROM go-base AS hugo
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="hugo" \
    && REPO="gohugoio/${BIN_NAME}" \
    && CGO_ENABLED=0 go install \
    --tags extended \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM go-base AS pulumi
RUN set -x && cd "$(mktemp -d)" \
    && BIN_NAME="pulumi" \
    && curl -fsSL https://get.${BIN_NAME}.com | sh \
    && mv ${HOME}/.${BIN_NAME}/bin/${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM go-base AS tinygo
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="tinygo" \
    && REPO="${BIN_NAME}-org/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH)" \
    && TAR_NAME="${BIN_NAME}${VERSION}.${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv ${BIN_NAME}/bin/${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM go-base AS go
RUN upx -9 ${GOROOT}/bin/*

FROM go-tools AS tools
RUN upx -9 ${GOPATH}/bin/*

FROM go-base AS go-bins
COPY --from=dagger $GOBIN/dagger $GOBIN/dagger
COPY --from=flamegraph $GOBIN/flamegraph.pl $GOBIN/flamegraph.pl
COPY --from=flamegraph $GOBIN/stackcollapse-go.pl $GOBIN/stackcollapse-go.pl
COPY --from=flamegraph $GOBIN/stackcollapse.pl $GOBIN/stackcollapse.pl
COPY --from=fzf $GOBIN/fzf $GOBIN/fzf
COPY --from=gh $GOBIN/gh $GOBIN/gh
COPY --from=golangci-lint $GOBIN/golangci-lint $GOBIN/golangci-lint
COPY --from=gopls $GOBIN/gopls $GOBIN/gopls
COPY --from=guru $GOBIN/guru $GOBIN/guru
COPY --from=hugo $GOBIN/hugo $GOBIN/hugo
COPY --from=pulumi $GOBIN/pulumi $GOBIN/pulumi
COPY --from=tinygo $GOBIN/tinygo $GOBIN/tinygo
# COPY --from=markdown2medium $GOBIN/markdown2medium $GOBIN/markdown2medium

FROM scratch
ENV GOROOT=/usr/local/go
ENV GOPATH=/go
COPY --from=go $GOROOT/bin $GOROOT/bin
COPY --from=go $GOROOT/src $GOROOT/src
COPY --from=go $GOROOT/lib $GOROOT/lib
COPY --from=go $GOROOT/pkg $GOROOT/pkg
COPY --from=go $GOROOT/misc $GOROOT/misc
COPY --from=go-bins $GOPATH/bin $GOPATH/bin
COPY --from=tools $GOPATH/bin $GOPATH/bin
