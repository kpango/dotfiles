FROM --platform=$BUILDPLATFORM kpango/dev-base:latest AS go-base

ARG TARGETOS
ARG TARGETARCH

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV XARCH x86_64

ENV GO_VERSION 1.17beta1
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
ENV GITHUB https://${GITHUBCOM}
ENV PATH ${PATH}:${GOROOT}/bin:${GOPATH}/bin

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

FROM go-base AS act
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="act" \
    && REPO="nektos/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS air
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="air" \
    && REPO="cosmtrek/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS chidley
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="chidley" \
    && REPO="gnewton/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS dbmate
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="dbmate" \
    && REPO="amacneil/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS direnv
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="direnv" \
    && REPO="direnv/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS dlv
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="dlv" \
    && REPO="go-delve/delve" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS dragon-imports
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="dragon-imports" \
    && REPO="rerost/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS duf
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="duf" \
    && REPO="muesli/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS efm
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="efm-langserver" \
    && REPO="mattn/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS errcheck
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="errcheck" \
    && REPO="kisielk/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS evans
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="evans" \
    && REPO="ktr0731/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS fillstruct
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="fillstruct" \
    && REPO="davidrjenni/reftools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS fillswitch
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="fillswitch" \
    && REPO="davidrjenni/reftools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS fixplurals
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="fixplurals" \
    && REPO="davidrjenni/reftools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS flamegraph
RUN set -x; cd "$(mktemp -d)" \
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
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="ghq" \
    && REPO="x-motemen/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS ghz
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="ghz" \
    && REPO="bojand/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gocode
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gocode" \
    && REPO="nsf/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS godef
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="godef" \
    && REPO="rogpeppe/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gofumpt
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gofumpt" \
    && REPO="mvdan.cc/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gofumports
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gofumports" \
    && REPO="mvdan.cc/gofumpt/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS goimports
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="goimports" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS goimports-update-ignore
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="goimports-update-ignore" \
    && REPO="pwaller/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gojson
RUN set -x; cd "$(mktemp -d)" \
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
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="golines" \
    && REPO="segmentio/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS golint
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="golint" \
    && REPO="golang.org/x/lint" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gomodifytags
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gomodifytags" \
    && REPO="fatih/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gopls
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gopls" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gorename
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gorename" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS goreturns
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="goreturns" \
    && REPO="sqs/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "sourcegraph.com/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gosec
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gosec" \
    && REPO="securego/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gotags
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gotags" \
    && REPO="jstemmer/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gotests
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gotests" \
    && REPO="cweill/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS gowrap
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="gowrap" \
    && REPO="hexdigest/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS grpcurl
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="grpcurl" \
    && REPO="fullstorydev/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS guru
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="guru" \
    && REPO="golang.org/x/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS hub
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="hub" \
    && REPO="github/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS hugo
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="hugo" \
    && REPO="gohugoio/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS iferr
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="iferr" \
    && REPO="koron/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS impl
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="impl" \
    && REPO="josharian/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS k6
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="k6" \
    && REPO="go.k6.io/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS keyify
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="keyify" \
    && REPO="honnef.co/go/tools" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS markdown2medium
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="markdown2medium" \
    && REPO="kpango/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS mockgen
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="mockgen" \
    && REPO="golang/mock" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS panicparse
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="pp" \
    && REPO="maruel/panicparse" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@master" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS prototool
RUN set -x; cd "$(mktemp -d)" \
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
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="reddit2wallpaper" \
    && REPO="mattiamari/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS ruleguard
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="ruleguard" \
    && REPO="quasilyte/go-${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS sqls
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="sqls" \
    && REPO="lighttiger2505/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS swagger
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="swagger" \
    && REPO="go-${BIN_NAME}/go-${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS syncmap
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="syncmap" \
    && REPO="a8m/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS tinygo
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="tinygo" \
    && REPO="${BIN_NAME}-org/${BIN_NAME}" \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH | sed 's/arm64/arm/')" \
    && TINYGO_VERSION="$(curl --silent ${GITHUB}/${REPO}/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/${REPO}/releases/download/v${TINYGO_VERSION}/${BIN_NAME}${TINYGO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && tar zxf "${BIN_NAME}${TINYGO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && mv ${BIN_NAME}/bin/${BIN_NAME} ${GOPATH}/bin/${BIN_NAME} \
    && upx -9 ${GOPATH}/bin/${BIN_NAME}

FROM go-base AS vegeta
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="vegeta" \
    && REPO="tsenart/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS vgrun
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="vgrun" \
    && REPO="vugu/${BIN_NAME}" \
    && GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    "${GITHUBCOM}/${REPO}@latest" \
    && chmod a+x "${GOPATH}/bin/${BIN_NAME}" \
    && upx -9 "${GOPATH}/bin/${BIN_NAME}"

FROM go-base AS xo
RUN set -x; cd "$(mktemp -d)" \
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
COPY --from=act $GOPATH/bin/act $GOPATH/bin/act
COPY --from=air $GOPATH/bin/air $GOPATH/bin/air
COPY --from=chidley $GOPATH/bin/chidley $GOPATH/bin/chidley
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
COPY --from=gocode $GOPATH/bin/gocode $GOPATH/bin/gocode
COPY --from=godef $GOPATH/bin/godef $GOPATH/bin/godef
COPY --from=gofumports $GOPATH/bin/gofumports $GOPATH/bin/gofumports
COPY --from=gofumpt $GOPATH/bin/gofumpt $GOPATH/bin/gofumpt
COPY --from=goimports $GOPATH/bin/goimports $GOPATH/bin/goimports
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
COPY --from=gowrap $GOPATH/bin/gowrap $GOPATH/bin/gowrap
COPY --from=grpcurl $GOPATH/bin/grpcurl $GOPATH/bin/grpcurl
COPY --from=guru $GOPATH/bin/guru $GOPATH/bin/guru
COPY --from=hub $GOPATH/bin/hub $GOPATH/bin/hub
COPY --from=hugo $GOPATH/bin/hugo $GOPATH/bin/hugo
COPY --from=iferr $GOPATH/bin/iferr $GOPATH/bin/iferr
COPY --from=impl $GOPATH/bin/impl $GOPATH/bin/impl
COPY --from=k6 $GOPATH/bin/k6 $GOPATH/bin/k6
COPY --from=keyify $GOPATH/bin/keyify $GOPATH/bin/keyify
COPY --from=markdown2medium $GOPATH/bin/markdown2medium $GOPATH/bin/markdown2medium
COPY --from=mockgen $GOPATH/bin/mockgen $GOPATH/bin/mockgen
COPY --from=panicparse $GOPATH/bin/pp $GOPATH/bin/pp
COPY --from=prototool $GOPATH/bin/prototool $GOPATH/bin/prototool
COPY --from=pulumi $GOPATH/bin/pulumi $GOPATH/bin/pulumi
COPY --from=reddit2wallpaper $GOPATH/bin/reddit2wallpaper $GOPATH/bin/reddit2wallpaper
COPY --from=ruleguard $GOPATH/bin/ruleguard $GOPATH/bin/ruleguard
COPY --from=sqls $GOPATH/bin/sqls $GOPATH/bin/sqls
COPY --from=swagger $GOPATH/bin/swagger $GOPATH/bin/swagger
COPY --from=syncmap $GOPATH/bin/syncmap $GOPATH/bin/syncmap
COPY --from=tinygo $GOPATH/bin/tinygo $GOPATH/bin/tinygo
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
