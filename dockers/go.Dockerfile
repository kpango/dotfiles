# syntax = docker/dockerfile:latest
FROM --platform=$BUILDPLATFORM kpango/base:latest AS go-base

ARG TARGETOS
ARG TARGETARCH

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV AARCH aarch_64
ENV XARCH x86_64

ENV GO111MODULE on
ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ENV LANG en_US.UTF-8
ENV GOROOT /opt/go
ENV GOPATH /go
ENV GOBIN ${GOPATH}/bin
ENV GOARCH ${ARCH}
ENV GOOS ${OS}
ENV GOFLAGS "-ldflags=-w -ldflags=-s"
ENV GOORG "golang.org"
ENV GODEV "https://go.dev"
ENV GITHUBCOM github.com
ENV API_GITHUB https://api.${GITHUBCOM}/repos
ENV GITHUB https://${GITHUBCOM}
ENV PATH ${PATH}:${GOROOT}/bin:${GOBIN}
ENV RELEASE_DL releases/download
ENV RELEASE_LATEST releases/latest
ENV GO_FLAGS "-trimpath -modcacherw -a -tags netgo"

WORKDIR /tmp

RUN apt update -y \
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
    && [ -n "${GO_VERSION}" ] || { echo "Error: VERSION is empty. curl response was: ${BODY}" >&2; exit 1; } \
    && TAR_NAME="${GO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && curl -fsSLO "${GODEV}/dl/${TAR_NAME}" \
    && tar zxf "${TAR_NAME}" \
    && rm "${TAR_NAME}" \
    && mv ${BIN_NAME} ${GOROOT} \
    && mkdir -p ${GOBIN} \
    && ${BIN_NAME} version

COPY go.env "${GOROOT}/go.env"

# FROM --platform=$BUILDPLATFORM go-base AS act
# RUN set -x && cd "$(mktemp -d)" \
#     && BIN_NAME="act" \
#     && REPO="nektos/${BIN_NAME}" \
#     && go install \
#     ${GO_FLAGS} \
#     "${GITHUBCOM}/${REPO}@upgrade" \
#     && chmod a+x "${GOBIN}/${BIN_NAME}" \
#     && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS air
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="air" \
    && REPO="air-verse/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS buf
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="buf" \
    && REPO="bufbuild/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS chidley
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="chidley" \
    && REPO="gnewton/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

# FROM --platform=$BUILDPLATFORM go-base AS dataloaden
# RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
#     --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
#     --mount=type=tmpfs,target="${GOPATH}/src" \
#     set -x && cd "$(mktemp -d)" \
#     && BIN_NAME="dataloaden" \
#     && REPO="vektah/${BIN_NAME}" \
#     && go install \
#     ${GO_FLAGS} \
#     "${GITHUBCOM}/${REPO}@upgrade" \
#     && chmod a+x "${GOBIN}/${BIN_NAME}" \
#     && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS dagger
RUN set -x && cd "$(mktemp -d)" \
    && BIN_NAME="dagger" \
    && curl -fsSL https://dl.${BIN_NAME}.io/${BIN_NAME}/install.sh | BIN_DIR=${GOBIN} sh \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM go-base AS dbmate
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="dbmate" \
    && REPO="amacneil/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS direnv
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="direnv" \
    && REPO="direnv/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS dlayer
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="dlayer" \
    && REPO="orisano/${BIN_NAME}" \
    && GOOS=${GOOS} GOARCH=${GOARCH} \
    CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS dlv
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="dlv" \
    && REPO="go-delve/delve" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS dragon-imports
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="dragon-imports" \
    && REPO="rerost/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS duf
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="duf" \
    && REPO="muesli/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS efm
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="efm-langserver" \
    && REPO="mattn/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS errcheck
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="errcheck" \
    && REPO="kisielk/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS evans
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="evans" \
    && REPO="ktr0731/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS fillstruct
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="fillstruct" \
    && REPO="davidrjenni/reftools" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS fillswitch
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="fillswitch" \
    && REPO="davidrjenni/reftools" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS fixplurals
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="fixplurals" \
    && REPO="davidrjenni/reftools" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS flamegraph
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

FROM --platform=$BUILDPLATFORM go-base AS fzf
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
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv ${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM go-base AS ghq
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="ghq" \
    && REPO="x-motemen/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS ghz
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="ghz" \
    && REPO="bojand/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS git-codereview
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="git-codereview" \
    && REPO="${GOORG}/x/review" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${REPO}/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gitleaks
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gitleaks" \
    && REPO="zricethezav/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"


FROM --platform=$BUILDPLATFORM go-base AS glice
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="glice" \
    && REPO="ribice/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS go-contrib-init
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="go-contrib-init" \
    && REPO="${GOORG}/x/tools" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS go-task
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="task" \
    && REPO="go-${BIN_NAME}/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/v3/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gocode
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gocode" \
    && REPO="nsf/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gofumpt
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gofumpt" \
    && REPO="mvdan.cc/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS goimports
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="goimports" \
    && REPO="${GOORG}/x/tools" \
    && go install \
    ${GO_FLAGS} \
    "${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS goimports-reviser
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="goimports-reviser" \
    && REPO="incu6us/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS goimports-update-ignore
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="goimports-update-ignore" \
    && REPO="pwaller/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gojson
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gojson" \
    && REPO="y4v8/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM golangci/golangci-lint:latest AS golangci-lint-base
FROM --platform=$BUILDPLATFORM go-base AS golangci-lint
ENV BIN_NAME golangci-lint
COPY --from=golangci-lint-base /usr/bin/${BIN_NAME} ${GOBIN}/${BIN_NAME}
RUN upx -9 ${GOBIN}/${BIN_NAME}


FROM --platform=$BUILDPLATFORM go-base AS golines
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="golines" \
    && REPO="segmentio/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS golint
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="golint" \
    && REPO="${GOORG}/x/lint" \
    && go install \
    ${GO_FLAGS} \
    "${REPO}/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gomodifytags
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gomodifytags" \
    && REPO="fatih/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gopls
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

FROM --platform=$BUILDPLATFORM go-base AS gorename
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gorename" \
    && REPO="${GOORG}/x/tools" \
    && go install \
    ${GO_FLAGS} \
    "${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS goreturns
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="goreturns" \
    && REPO="sqs/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gosec
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gosec" \
    && REPO="securego/${BIN_NAME}" \
    && GOOS=${GOOS} GOARCH=${GOARCH} \
    CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gotags
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gotags" \
    && REPO="jstemmer/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gotestfmt
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gotestfmt" \
    && REPO="gotesttools/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/v2/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gotests
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gotests" \
    && REPO="cweill/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gotip
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && echo "gcc VERSION is $(gcc --version)" \
    && BIN_NAME="gotip" \
    && ORG="${GOORG}/dl" \
    && REPO="${ORG}/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS govulncheck
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="govulncheck" \
    && REPO="${GOORG}/x/vuln" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gowrap
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gowrap" \
    && REPO="hexdigest/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS gqlgen
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="gqlgen" \
    && REPO="99designs/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@v0.17.46" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"
    # TODO: update
    # "${GITHUBCOM}/${REPO}@upgrade" \

FROM --platform=$BUILDPLATFORM go-base AS grpcurl
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="grpcurl" \
    && REPO="fullstorydev/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

# FROM --platform=$BUILDPLATFORM go-base AS grype
# RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
#     --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
#     --mount=type=tmpfs,target="${GOPATH}/src" \
#     set -x && cd "$(mktemp -d)" \
#     && BIN_NAME="grype" \
#     && REPO="anchore/${BIN_NAME}" \
#     && CGO_ENABLED=0 \
#     go install \
#     ${GO_FLAGS} \
#     "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
#     && chmod a+x "${GOBIN}/${BIN_NAME}" \
#     && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS guru
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

FROM --platform=$BUILDPLATFORM go-base AS hub
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="hub" \
    && REPO="github/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS hugo
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

FROM --platform=$BUILDPLATFORM go-base AS iferr
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="iferr" \
    && REPO="koron/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS impl
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="impl" \
    && REPO="josharian/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS k6
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="k6" \
    && REPO="go.${BIN_NAME}.io/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${REPO}@master" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS keyify
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="keyify" \
    && REPO="honnef.co/go/tools" \
    && go install \
    ${GO_FLAGS} \
    "${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS kratos
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kratos" \
    && REPO="go-kratos/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS licenses
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="go-licenses" \
    && REPO="google/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS markdown2medium
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="markdown2medium" \
    && REPO="kpango/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS mockgen
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="mockgen" \
    && REPO="golang/mock" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

# FROM --platform=$BUILDPLATFORM go-base AS panicparse
# RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
#     --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
#     --mount=type=tmpfs,target="${GOPATH}/src" \
#     set -x && cd "$(mktemp -d)" \
#     && BIN_NAME="pp" \
#     && REPO="maruel/panicparse" \
#     && go install \
#     ${GO_FLAGS} \
#     "${GITHUBCOM}/${REPO}/v2/cmd/${BIN_NAME}@master" \
#     && chmod a+x "${GOBIN}/${BIN_NAME}" \
#     && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS protoc-gen-connect-go
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="protoc-gen-connect-go" \
    && REPO="bufbuild/connect-go" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS protoc-gen-go
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="protoc-gen-go" \
    && REPO="protobuf" \
    && go install \
    ${GO_FLAGS} \
    "google.${GOORG}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS prototool
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="prototool" \
    && REPO="uber/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@dev" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS pulumi
RUN set -x && cd "$(mktemp -d)" \
    && BIN_NAME="pulumi" \
    && curl -fsSL https://get.${BIN_NAME}.com | sh \
    && mv ${HOME}/.${BIN_NAME}/bin/${BIN_NAME} ${GOBIN}/${BIN_NAME} \
    && upx -9 ${GOBIN}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM go-base AS reddit2wallpaper
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="reddit2wallpaper" \
    && REPO="mattiamari/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS ruleguard
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="ruleguard" \
    && REPO="quasilyte/go-${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS shfmt
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="shfmt" \
    && REPO="mvdan.cc/sh/v3/cmd/${BIN_NAME}" \
    && go install ${GO_FLAGS} ${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS strictgoimports
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="strictgoimports" \
    && REPO="momotaro98/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS swagger
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="swagger" \
    && REPO="go-${BIN_NAME}/go-${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

# FROM --platform=$BUILDPLATFORM go-base AS syft
# RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
#     --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
#     --mount=type=tmpfs,target="${GOPATH}/src" \
#     set -x && cd "$(mktemp -d)" \
#     && BIN_NAME="syft" \
#     && REPO="anchore/${BIN_NAME}" \
#     && CGO_ENABLED=0 \
#     go install \
#     ${GO_FLAGS} \
#     "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
#     && chmod a+x "${GOBIN}/${BIN_NAME}" \
#     && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS syncmap
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="syncmap" \
    && REPO="a8m/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS tinygo
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

FROM --platform=$BUILDPLATFORM go-base AS tparse
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="tparse" \
    && REPO="mfridman/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS vegeta
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="vegeta" \
    && REPO="tsenart/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS vgrun
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="vgrun" \
    && REPO="vugu/${BIN_NAME}" \
    && go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS xo
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="xo" \
    && REPO="${BIN_NAME}/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS yamlfmt
RUN --mount=type=cache,target="${GOPATH}/pkg",id="go-build-${ARCH}" \
    --mount=type=cache,target="${HOME}/.cache/go-build",id="go-build-${ARCH}" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="yamlfmt" \
    && REPO="google/${BIN_NAME}" \
    && CGO_ENABLED=0 \
    go install \
    ${GO_FLAGS} \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@upgrade" \
    && chmod a+x "${GOBIN}/${BIN_NAME}" \
    && upx -9 "${GOBIN}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM go-base AS go
RUN upx -9 ${GOROOT}/bin/*

FROM --platform=$BUILDPLATFORM go-base AS go-bins
# COPY --from=act $GOBIN/act $GOBIN/act
COPY --from=air $GOBIN/air $GOBIN/air
COPY --from=buf $GOBIN/buf $GOBIN/buf
COPY --from=chidley $GOBIN/chidley $GOBIN/chidley
# COPY --from=dataloaden $GOBIN/dataloaden $GOBIN/dataloaden
COPY --from=dagger $GOBIN/dagger $GOBIN/dagger
COPY --from=dbmate $GOBIN/dbmate $GOBIN/dbmate
COPY --from=direnv $GOBIN/direnv $GOBIN/direnv
COPY --from=dlayer $GOBIN/dlayer $GOBIN/dlayer
COPY --from=dlv $GOBIN/dlv $GOBIN/dlv
COPY --from=dragon-imports $GOBIN/dragon-imports $GOBIN/dragon-imports
COPY --from=duf $GOBIN/duf $GOBIN/duf
COPY --from=efm $GOBIN/efm-langserver $GOBIN/efm-langserver
COPY --from=errcheck $GOBIN/errcheck $GOBIN/errcheck
COPY --from=evans $GOBIN/evans $GOBIN/evans
COPY --from=fillstruct $GOBIN/fillstruct $GOBIN/fillstruct
COPY --from=fillswitch $GOBIN/fillswitch $GOBIN/fillswitch
COPY --from=fixplurals $GOBIN/fixplurals $GOBIN/fixplurals
COPY --from=flamegraph $GOBIN/flamegraph.pl $GOBIN/flamegraph.pl
COPY --from=flamegraph $GOBIN/stackcollapse-go.pl $GOBIN/stackcollapse-go.pl
COPY --from=flamegraph $GOBIN/stackcollapse.pl $GOBIN/stackcollapse.pl
COPY --from=fzf $GOBIN/fzf $GOBIN/fzf
COPY --from=ghq $GOBIN/ghq $GOBIN/ghq
COPY --from=ghz $GOBIN/ghz $GOBIN/ghz
COPY --from=git-codereview $GOBIN/git-codereview $GOBIN/git-codereview
COPY --from=gitleaks $GOBIN/gitleaks $GOBIN/gitleaks
COPY --from=glice $GOBIN/glice $GOBIN/glice
COPY --from=go-contrib-init $GOBIN/go-contrib-init $GOBIN/go-contrib-init
COPY --from=go-task $GOBIN/task $GOBIN/task
COPY --from=gocode $GOBIN/gocode $GOBIN/gocode
COPY --from=gofumpt $GOBIN/gofumpt $GOBIN/gofumpt
COPY --from=goimports $GOBIN/goimports $GOBIN/goimports
COPY --from=goimports-reviser $GOBIN/goimports-reviser $GOBIN/goimports-reviser
COPY --from=goimports-update-ignore $GOBIN/goimports-update-ignore $GOBIN/goimports-update-ignore
COPY --from=gojson $GOBIN/gojson $GOBIN/gojson
COPY --from=golangci-lint $GOBIN/golangci-lint $GOBIN/golangci-lint
COPY --from=golines $GOBIN/golines $GOBIN/golines
COPY --from=golint $GOBIN/golint $GOBIN/golint
COPY --from=gomodifytags $GOBIN/gomodifytags $GOBIN/gomodifytags
COPY --from=gopls $GOBIN/gopls $GOBIN/gopls
COPY --from=gorename $GOBIN/gorename $GOBIN/gorename
COPY --from=goreturns $GOBIN/goreturns $GOBIN/goreturns
COPY --from=gosec $GOBIN/gosec $GOBIN/gosec
COPY --from=gotags $GOBIN/gotags $GOBIN/gotags
COPY --from=gotestfmt $GOBIN/gotestfmt $GOBIN/gotestfmt
COPY --from=gotests $GOBIN/gotests $GOBIN/gotests
COPY --from=gotip $GOBIN/gotip $GOBIN/gotip
COPY --from=govulncheck $GOBIN/govulncheck $GOBIN/govulncheck
COPY --from=gowrap $GOBIN/gowrap $GOBIN/gowrap
COPY --from=gqlgen $GOBIN/gqlgen $GOBIN/gqlgen
COPY --from=grpcurl $GOBIN/grpcurl $GOBIN/grpcurl
# COPY --from=grype $GOBIN/grype $GOBIN/grype
COPY --from=guru $GOBIN/guru $GOBIN/guru
COPY --from=hub $GOBIN/hub $GOBIN/hub
COPY --from=hugo $GOBIN/hugo $GOBIN/hugo
COPY --from=iferr $GOBIN/iferr $GOBIN/iferr
COPY --from=impl $GOBIN/impl $GOBIN/impl
COPY --from=k6 $GOBIN/k6 $GOBIN/k6
COPY --from=keyify $GOBIN/keyify $GOBIN/keyify
COPY --from=kratos $GOBIN/kratos $GOBIN/kratos
COPY --from=licenses $GOBIN/go-licenses $GOBIN/licenses
COPY --from=markdown2medium $GOBIN/markdown2medium $GOBIN/markdown2medium
COPY --from=mockgen $GOBIN/mockgen $GOBIN/mockgen
# COPY --from=panicparse $GOBIN/pp $GOBIN/pp
COPY --from=protoc-gen-connect-go $GOBIN/protoc-gen-connect-go $GOBIN/protoc-gen-connect-go
COPY --from=protoc-gen-go $GOBIN/protoc-gen-go $GOBIN/protoc-gen-go
COPY --from=prototool $GOBIN/prototool $GOBIN/prototool
COPY --from=pulumi $GOBIN/pulumi $GOBIN/pulumi
COPY --from=reddit2wallpaper $GOBIN/reddit2wallpaper $GOBIN/reddit2wallpaper
COPY --from=ruleguard $GOBIN/ruleguard $GOBIN/ruleguard
COPY --from=shfmt $GOBIN/shfmt $GOBIN/shfmt
COPY --from=strictgoimports $GOBIN/strictgoimports $GOBIN/strictgoimports
COPY --from=swagger $GOBIN/swagger $GOBIN/swagger
# COPY --from=syft $GOBIN/syft $GOBIN/syft
COPY --from=syncmap $GOBIN/syncmap $GOBIN/syncmap
COPY --from=tinygo $GOBIN/tinygo $GOBIN/tinygo
COPY --from=tparse $GOBIN/tparse $GOBIN/tparse
COPY --from=vegeta $GOBIN/vegeta $GOBIN/vegeta
COPY --from=vgrun $GOBIN/vgrun $GOBIN/vgrun
COPY --from=xo $GOBIN/xo $GOBIN/xo
COPY --from=yamlfmt $GOBIN/yamlfmt $GOBIN/yamlfmt

FROM --platform=$BUILDPLATFORM scratch
ENV GOROOT /opt/go
ENV GOPATH /go
COPY --from=go $GOROOT/bin $GOROOT/bin
COPY --from=go $GOROOT/src $GOROOT/src
COPY --from=go $GOROOT/lib $GOROOT/lib
COPY --from=go $GOROOT/pkg $GOROOT/pkg
COPY --from=go $GOROOT/misc $GOROOT/misc
COPY --from=go-bins $GOPATH/bin $GOPATH/bin
