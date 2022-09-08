# syntax = docker/dockerfile:latest
FROM --platform=$BUILDPLATFORM kpango/dev-base:latest AS go-base

ARG TARGETOS
ARG TARGETARCH

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV XARCH x86_64

ENV GO_VERSION 1.19.1
ENV GO111MODULE on
ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ENV LANG en_US.UTF-8
ENV GOROOT /opt/go
ENV GOPATH /go
ENV GOARCH=$TARGETARCH
ENV GOOS=$TARGETOS
ENV GOFLAGS "-ldflags=-w -ldflags=-s"
ENV GITHUBCOM github.com
ENV API_GITHUB https://api.github.com/repos
ENV GITHUB https://${GITHUBCOM}
ENV PATH ${PATH}:${GOROOT}/bin:${GOPATH}/bin
ENV RELEASE_DL releases/download
ENV RELEASE_LATEST releases/latest

WORKDIR /opt
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="go" \
    && TAR_NAME="${BIN_NAME}${GO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && curl -sSL -O "https://golang.org/dl/${TAR_NAME}" \
    && tar zxf "${TAR_NAME}" \
    && rm "${TAR_NAME}" \
    && mv ${BIN_NAME} /opt/${BIN_NAME} \
    && mkdir -p ${GOPATH}/bin \
    && ${BIN_NAME} version

# FROM go-base AS act
# RUN set -x; cd "$(mktemp -d)" \
#     && BIN_NAME="act" \
#     && REPO="nektos/${BIN_NAME}" \
#     && GO111MODULE=on go install  \
#     --ldflags "-s -w" --trimpath \
#     "${GITHUBCOM}/${REPO}@latest" \
#     && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
#     && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS air
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="air" \
    && REPO="cosmtrek/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS buf
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="buf" \
    && REPO="bufbuild/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS chidley
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="chidley" \
    && REPO="gnewton/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

# FROM go-base AS dataloaden
# RUN --mount=type=cache,target="${GOPATH}/pkg" \
#     --mount=type=cache,target="${HOME}/.cache/go-build" \
#     --mount=type=tmpfs,target="${GOPATH}/src" \
#     set -x; cd "$(mktemp -d)" \
#     && BIN_NAME="dataloaden" \
#     && REPO="vektah/${BIN_NAME}" \
#     && GO111MODULE=on go install  \
#     --ldflags "-s -w" --trimpath \
#     "${GITHUBCOM}/${REPO}@latest" \
#     && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
#     && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS dbmate
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="dbmate" \
    && REPO="amacneil/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS direnv
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="direnv" \
    && REPO="direnv/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS dlv
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="dlv" \
    && REPO="go-delve/delve" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS dragon-imports
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="dragon-imports" \
    && REPO="rerost/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS duf
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="duf" \
    && REPO="muesli/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS efm
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="efm-langserver" \
    && REPO="mattn/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS errcheck
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="errcheck" \
    && REPO="kisielk/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS evans
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="evans" \
    && REPO="ktr0731/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS fillstruct
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="fillstruct" \
    && REPO="davidrjenni/reftools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS fillswitch
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="fillswitch" \
    && REPO="davidrjenni/reftools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS fixplurals
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="fixplurals" \
    && REPO="davidrjenni/reftools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS flamegraph
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="FlameGraph" \
    && REPO="brendangregg/${BIN_NAME}" \
    && TMPDIR="/tmp/${BIN_NAME}" \
    && git clone --depth 1 \
        "${GITHUB}/${REPO}" \
        "${TMPDIR}" \
    && chmod -R a+x "${TMPDIR}" \
    && cp ${TMPDIR}/flamegraph.pl ${GOPATH}/bin/ \
    && cp ${TMPDIR}/stackcollapse.pl ${GOPATH}/bin/ \
    && cp ${TMPDIR}/stackcollapse-go.pl ${GOPATH}/bin/

FROM go-base AS ghq
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="ghq" \
    && REPO="x-motemen/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS ghz
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="ghz" \
    && REPO="bojand/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS git-codereview
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="git-codereview" \
    && REPO="golang.org/x/review" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gitleaks
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gitleaks" \
    && REPO="zricethezav/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"


FROM go-base AS glice
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="glice" \
    && REPO="ribice/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS go-contrib-init
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="go-contrib-init" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS go-task
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="task" \
    && REPO="go-${BIN_NAME}/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/v3/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gocode
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gocode" \
    && REPO="nsf/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS godef
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="godef" \
    && REPO="rogpeppe/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gofumpt
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gofumpt" \
    && REPO="mvdan.cc/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS goimports
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="goimports" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS goimports-reviser
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="goimports-reviser" \
    && REPO="incu6us/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS goimports-update-ignore
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="goimports-update-ignore" \
    && REPO="pwaller/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gojson
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gojson" \
    && REPO="y4v8/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM golangci/golangci-lint:latest AS golangci-lint-base
FROM go-base AS golangci-lint
ENV BIN_NAME golangci-lint
COPY --from=golangci-lint-base /usr/bin/${BIN_NAME} ${GOPATH}/bin/${BIN_NAME}
RUN upx -9 ${GOPATH}/bin/${BIN_NAME}


FROM go-base AS golines
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="golines" \
    && REPO="segmentio/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS golint
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="golint" \
    && REPO="golang.org/x/lint" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gomodifytags
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gomodifytags" \
    && REPO="fatih/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gopls
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gopls" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gorename
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gorename" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS goreturns
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="goreturns" \
    && REPO="sqs/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "sourcegraph.com/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gosec
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gosec" \
    && REPO="securego/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gotags
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gotags" \
    && REPO="jstemmer/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gotests
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gotests" \
    && REPO="cweill/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gotip
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gotip" \
    && ORG="golang.org/dl" \
    && REPO="${ORG}/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gowrap
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gowrap" \
    && REPO="hexdigest/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gqlgen
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gqlgen" \
    && REPO="99designs/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS grpcurl
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="grpcurl" \
    && REPO="fullstorydev/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS grype
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="grype" \
    && REPO="anchore/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS guru
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="guru" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS hub
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="hub" \
    && REPO="github/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS hugo
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="hugo" \
    && REPO="gohugoio/${BIN_NAME}" \
    && CGO_ENABLED=1 GO111MODULE=on go install  \
    --tags extended \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS iferr
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="iferr" \
    && REPO="koron/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS impl
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="impl" \
    && REPO="josharian/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS k6
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="k6" \
    && REPO="go.k6.io/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS keyify
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="keyify" \
    && REPO="honnef.co/go/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS kratos
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kratos" \
    && REPO="go-kratos/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/kratos@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS licenses
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="go-licenses" \
    && REPO="google/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS markdown2medium
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="markdown2medium" \
    && REPO="kpango/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS mockgen
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="mockgen" \
    && REPO="golang/mock" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS panicparse
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="pp" \
    && REPO="maruel/panicparse" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS protoc-gen-connect-go
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="protoc-gen-connect-go" \
    && REPO="bufbuild/connect-go" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS protoc-gen-go
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="protoc-gen-go" \
    && REPO="protobuf" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "google.golang.org/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS prototool
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="prototool" \
    && REPO="uber/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@dev" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS pulumi
RUN curl -fsSL https://get.pulumi.com | sh \
    && mv $HOME/.pulumi/bin/pulumi ${GOPATH}/bin/pulumi \
    && upx -9 ${GOPATH}/bin/pulumi

FROM go-base AS reddit2wallpaper
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="reddit2wallpaper" \
    && REPO="mattiamari/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS ruleguard
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="ruleguard" \
    && REPO="quasilyte/go-${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS sqls
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="sqls" \
    && REPO="lighttiger2505/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS strictgoimports
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="strictgoimports" \
    && REPO="momotaro98/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS swagger
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="swagger" \
    && REPO="go-${BIN_NAME}/go-${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS syft
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="syft" \
    && REPO="anchore/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS syncmap
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="syncmap" \
    && REPO="a8m/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS tinygo
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="tinygo" \
    && REPO="${BIN_NAME}-org/${BIN_NAME}" \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH | sed 's/arm64/arm/')" \
    && VERSION="$(curl --silent ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && TAR_NAME="${BIN_NAME}${VERSION}.${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv ${BIN_NAME}/bin/${BIN_NAME} ${GOPATH}/bin/${BIN_NAME} \
    && upx -9 ${GOPATH}/bin/${BIN_NAME}

FROM go-base AS tparse
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="tparse" \
    && REPO="mfridman/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS vegeta
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="vegeta" \
    && REPO="tsenart/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS vgrun
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="vgrun" \
    && REPO="vugu/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS xo
RUN --mount=type=cache,target="${GOPATH}/pkg" \
    --mount=type=cache,target="${HOME}/.cache/go-build" \
    --mount=type=tmpfs,target="${GOPATH}/src" \
    set -x; cd "$(mktemp -d)" \
    && BIN_NAME="xo" \
    && REPO="yyoshiki41/${BIN_NAME}" \
    # && REPO="xo/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS go
RUN upx -9 ${GOROOT}/bin/*

FROM go-base AS go-bins
# COPY --from=act $GOPATH/bin/act $GOPATH/bin/act
COPY --from=air $GOPATH/bin/air $GOPATH/bin/air
COPY --from=buf $GOPATH/bin/buf $GOPATH/bin/buf
COPY --from=chidley $GOPATH/bin/chidley $GOPATH/bin/chidley
# COPY --from=dataloaden $GOPATH/bin/dataloaden $GOPATH/bin/dataloaden
COPY --from=dbmate $GOPATH/bin/dbmate $GOPATH/bin/dbmate
COPY --from=direnv $GOPATH/bin/direnv $GOPATH/bin/direnv
COPY --from=dlv $GOPATH/bin/dlv $GOPATH/bin/dlv
COPY --from=dragon-imports $GOPATH/bin/dragon-imports $GOPATH/bin/dragon-imports
COPY --from=duf $GOPATH/bin/duf $GOPATH/bin/duf
COPY --from=efm $GOPATH/bin/efm-langserver $GOPATH/bin/efm-langserver
COPY --from=errcheck $GOPATH/bin/errcheck $GOPATH/bin/errcheck
COPY --from=evans $GOPATH/bin/evans $GOPATH/bin/evans
COPY --from=fillstruct $GOPATH/bin/fillstruct $GOPATH/bin/fillstruct
COPY --from=fillswitch $GOPATH/bin/fillswitch $GOPATH/bin/fillswitch
COPY --from=fixplurals $GOPATH/bin/fixplurals $GOPATH/bin/fixplurals
COPY --from=flamegraph $GOPATH/bin/flamegraph.pl $GOPATH/bin/flamegraph.pl
COPY --from=flamegraph $GOPATH/bin/stackcollapse-go.pl $GOPATH/bin/stackcollapse-go.pl
COPY --from=flamegraph $GOPATH/bin/stackcollapse.pl $GOPATH/bin/stackcollapse.pl
COPY --from=ghq $GOPATH/bin/ghq $GOPATH/bin/ghq
COPY --from=ghz $GOPATH/bin/ghz $GOPATH/bin/ghz
COPY --from=git-codereview $GOPATH/bin/git-codereview $GOPATH/bin/git-codereview
COPY --from=gitleaks $GOPATH/bin/gitleaks $GOPATH/bin/gitleaks
COPY --from=glice $GOPATH/bin/glice $GOPATH/bin/glice
COPY --from=go-contrib-init $GOPATH/bin/go-contrib-init $GOPATH/bin/go-contrib-init
COPY --from=go-task $GOPATH/bin/task $GOPATH/bin/task
COPY --from=gocode $GOPATH/bin/gocode $GOPATH/bin/gocode
COPY --from=godef $GOPATH/bin/godef $GOPATH/bin/godef
COPY --from=gofumpt $GOPATH/bin/gofumpt $GOPATH/bin/gofumpt
COPY --from=goimports $GOPATH/bin/goimports $GOPATH/bin/goimports
COPY --from=goimports-reviser $GOPATH/bin/goimports-reviser $GOPATH/bin/goimports-reviser
COPY --from=goimports-update-ignore $GOPATH/bin/goimports-update-ignore $GOPATH/bin/goimports-update-ignore
COPY --from=gojson $GOPATH/bin/gojson $GOPATH/bin/gojson
COPY --from=golangci-lint $GOPATH/bin/golangci-lint $GOPATH/bin/golangci-lint
COPY --from=golines $GOPATH/bin/golines $GOPATH/bin/golines
COPY --from=golint $GOPATH/bin/golint $GOPATH/bin/golint
COPY --from=gomodifytags $GOPATH/bin/gomodifytags $GOPATH/bin/gomodifytags
COPY --from=gopls $GOPATH/bin/gopls $GOPATH/bin/gopls
COPY --from=gorename $GOPATH/bin/gorename $GOPATH/bin/gorename
COPY --from=goreturns $GOPATH/bin/goreturns $GOPATH/bin/goreturns
COPY --from=gosec $GOPATH/bin/gosec $GOPATH/bin/gosec
COPY --from=gotags $GOPATH/bin/gotags $GOPATH/bin/gotags
COPY --from=gotests $GOPATH/bin/gotests $GOPATH/bin/gotests
COPY --from=gotip $GOPATH/bin/gotip $GOPATH/bin/gotip
COPY --from=gowrap $GOPATH/bin/gowrap $GOPATH/bin/gowrap
COPY --from=gqlgen $GOPATH/bin/gqlgen $GOPATH/bin/gqlgen
COPY --from=grpcurl $GOPATH/bin/grpcurl $GOPATH/bin/grpcurl
COPY --from=grype $GOPATH/bin/grype $GOPATH/bin/grype
COPY --from=guru $GOPATH/bin/guru $GOPATH/bin/guru
COPY --from=hub $GOPATH/bin/hub $GOPATH/bin/hub
COPY --from=hugo $GOPATH/bin/hugo $GOPATH/bin/hugo
COPY --from=iferr $GOPATH/bin/iferr $GOPATH/bin/iferr
COPY --from=impl $GOPATH/bin/impl $GOPATH/bin/impl
COPY --from=k6 $GOPATH/bin/k6 $GOPATH/bin/k6
COPY --from=keyify $GOPATH/bin/keyify $GOPATH/bin/keyify
COPY --from=kratos $GOPATH/bin/kratos $GOPATH/bin/kratos
COPY --from=licenses $GOPATH/bin/go-licenses $GOPATH/bin/licenses
COPY --from=markdown2medium $GOPATH/bin/markdown2medium $GOPATH/bin/markdown2medium
COPY --from=mockgen $GOPATH/bin/mockgen $GOPATH/bin/mockgen
COPY --from=panicparse $GOPATH/bin/pp $GOPATH/bin/pp
COPY --from=protoc-gen-connect-go $GOPATH/bin/protoc-gen-connect-go $GOPATH/bin/protoc-gen-connect-go
COPY --from=protoc-gen-go $GOPATH/bin/protoc-gen-go $GOPATH/bin/protoc-gen-go
COPY --from=prototool $GOPATH/bin/prototool $GOPATH/bin/prototool
COPY --from=pulumi $GOPATH/bin/pulumi $GOPATH/bin/pulumi
COPY --from=reddit2wallpaper $GOPATH/bin/reddit2wallpaper $GOPATH/bin/reddit2wallpaper
COPY --from=ruleguard $GOPATH/bin/ruleguard $GOPATH/bin/ruleguard
COPY --from=sqls $GOPATH/bin/sqls $GOPATH/bin/sqls
COPY --from=strictgoimports $GOPATH/bin/strictgoimports $GOPATH/bin/strictgoimports
COPY --from=swagger $GOPATH/bin/swagger $GOPATH/bin/swagger
COPY --from=syft $GOPATH/bin/syft $GOPATH/bin/syft
COPY --from=syncmap $GOPATH/bin/syncmap $GOPATH/bin/syncmap
COPY --from=tinygo $GOPATH/bin/tinygo $GOPATH/bin/tinygo
COPY --from=tparse $GOPATH/bin/tparse $GOPATH/bin/tparse
COPY --from=vegeta $GOPATH/bin/vegeta $GOPATH/bin/vegeta
COPY --from=vgrun $GOPATH/bin/vgrun $GOPATH/bin/vgrun
COPY --from=xo $GOPATH/bin/xo $GOPATH/bin/xo

FROM scratch
ENV GOROOT /opt/go
ENV GOPATH /go
COPY --from=go $GOROOT/bin $GOROOT/bin
COPY --from=go $GOROOT/src $GOROOT/src
COPY --from=go $GOROOT/lib $GOROOT/lib
COPY --from=go $GOROOT/pkg $GOROOT/pkg
COPY --from=go $GOROOT/misc $GOROOT/misc
COPY --from=go-bins $GOPATH/bin $GOPATH/bin
