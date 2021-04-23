FROM --platform=$BUILDPLATFORM kpango/dev-base:latest AS go-base

ARG TARGETOS
ARG TARGETARCH

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV XARCH x86_64

ENV GO_VERSION 1.16.3
ENV GO111MODULE on
ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ENV LANG en_US.UTF-8
ENV GOROOT /opt/go
ENV GOPATH /go
ENV GOARCH=$TARGETARCH
ENV GOOS=$TARGETOS
ENV GOFLAGS "-ldflags=-w -ldflags=-s"

WORKDIR /opt
RUN curl -sSL -O "https://dl.google.com/go/go${GO_VERSION}.${TARGETOS}-${TARGETARCH}.tar.gz" \
    && tar zxf "go${GO_VERSION}.${TARGETOS}-${TARGETARCH}.tar.gz" \
    && rm "go${GO_VERSION}.${TARGETOS}-${TARGETARCH}.tar.gz" \
    && ln -s /opt/go/bin/go /usr/bin/ \
    && mkdir -p ${GOPATH}/bin

FROM go-base AS gojson
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/y4v8/gojson/gojson@latest \
    && upx -9 ${GOPATH}/bin/gojson

FROM go-base AS syncmap
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/a8m/syncmap@latest \
    && upx -9 ${GOPATH}/bin/syncmap

FROM go-base AS gotests
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/cweill/gotests/gotests@latest \
    && upx -9 ${GOPATH}/bin/gotests

FROM go-base AS fillstruct
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/davidrjenni/reftools/cmd/fillstruct@latest \
    && upx -9 ${GOPATH}/bin/fillstruct

FROM go-base AS gomodifytags
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/fatih/gomodifytags@latest \
    && upx -9 ${GOPATH}/bin/gomodifytags

FROM go-base AS chidley
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/gnewton/chidley@latest \
    && upx -9 ${GOPATH}/bin/chidley

FROM go-base AS dlv
RUN git clone --depth 1 https://github.com/go-delve/delve.git \
    ${GOPATH}/src/github.com/go-delve/delve \
    && cd ${GOPATH}/src/github.com/go-delve/delve \
    && make install \
    && upx -9 ${GOPATH}/bin/dlv

FROM go-base AS hub
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/github/hub@latest \
    && upx -9 ${GOPATH}/bin/hub

FROM go-base AS impl
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/josharian/impl@latest \
    && upx -9 ${GOPATH}/bin/impl

FROM go-base AS gotags
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/jstemmer/gotags@latest \
    && upx -9 ${GOPATH}/bin/gotags

FROM go-base AS errcheck
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/kisielk/errcheck@latest \
    && upx -9 ${GOPATH}/bin/errcheck

FROM go-base AS iferr
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/koron/iferr@latest \
    && upx -9 ${GOPATH}/bin/iferr

FROM go-base AS dragon-imports
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/rerost/dragon-imports/cmd/dragon-imports@latest \
    && upx -9 ${GOPATH}/bin/dragon-imports


FROM go-base AS dbmate
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/amacneil/dbmate@latest \
    && upx -9 ${GOPATH}/bin/iferr

FROM go-base AS air
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/cosmtrek/air@latest \
    && upx -9 ${GOPATH}/bin/air

FROM go-base AS swagger
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/go-swagger/go-swagger/cmd/swagger@latest \
    && upx -9 ${GOPATH}/bin/swagger

FROM go-base AS mockgen
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/golang/mock/mockgen@latest \
    && upx -9 ${GOPATH}/bin/mockgen

FROM go-base AS xo
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/yyoshiki41/xo@latest \
    && upx -9 ${GOPATH}/bin/xo
    # github.com/xo/xo@latest \


# FROM go-base AS grpcurl
# RUN set -x; cd "$(mktemp -d)" \
#     && OS="$(go env GOOS)" \
#     && NAME="grpcurl" \
#     && ORG="fullstorydev" \
#     && REPO="${ORG}/${NAME}" \
#     && GRPCURL_VERSION="$(curl --silent https://github.com/${REPO}/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
#     && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
#     && curl -fsSLO "https://github.com/${REPO}/releases/download/v${GRPCURL_VERSION}/${NAME}_${GRPCURL_VERSION}_${OS}_${ARCH}.tar.gz" \
#     && tar zxf "${NAME}_${GRPCURL_VERSION}_${OS}_${ARCH}.tar.gz" \
#     && mv ${NAME} ${GOPATH}/bin/${NAME} \
#     && upx -9 ${GOPATH}/bin/${NAME}

FROM go-base AS ghq
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/x-motemen/ghq@latest \
    && upx -9 ${GOPATH}/bin/ghq

FROM go-base AS gocode
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/nsf/gocode@latest \
    && upx -9 ${GOPATH}/bin/gocode

FROM go-base AS godef
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/rogpeppe/godef@latest \
    && upx -9 ${GOPATH}/bin/godef

# FROM go-base AS act
# RUN GO111MODULE=on go install  \
#     --ldflags "-s -w" --trimpath \
#     github.com/nektos/act \
#     && upx -9 ${GOPATH}/bin/act

FROM go-base AS efm
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/mattn/efm-langserver@latest \
    && upx -9 ${GOPATH}/bin/efm-langserver

FROM go-base AS golint
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/lint/golint@latest \
    && upx -9 ${GOPATH}/bin/golint

FROM go-base AS gofumpt
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    mvdan.cc/gofumpt@latest \
    && upx -9 ${GOPATH}/bin/gofumpt

FROM go-base AS gofumports
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    mvdan.cc/gofumpt/gofumports@latest \
    && upx -9 ${GOPATH}/bin/gofumports

FROM go-base AS goimports
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/cmd/goimports@latest \
    && upx -9 ${GOPATH}/bin/goimports

FROM go-base AS goimports-update-ignore
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/pwaller/goimports-update-ignore@latest \
    && upx -9 ${GOPATH}/bin/goimports-update-ignore

FROM go-base AS ghz
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/bojand/ghz/cmd/ghz@latest \
    && upx -9 ${GOPATH}/bin/ghz

FROM go-base AS gopls
RUN GO111MODULE=on go get \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/gopls@master \
    golang.org/x/tools@master \
    && upx -9 ${GOPATH}/bin/gopls

FROM go-base AS gorename
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/cmd/gorename@latest \
    && upx -9 ${GOPATH}/bin/gorename

FROM go-base AS guru
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/cmd/guru@latest \
    && upx -9 ${GOPATH}/bin/guru

FROM go-base AS keyify
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    honnef.co/go/tools/cmd/keyify@latest \
    && upx -9 ${GOPATH}/bin/keyify

FROM go-base AS goreturns
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    sourcegraph.com/sqs/goreturns@latest \
    && upx -9 ${GOPATH}/bin/goreturns

# FROM go-base AS diago
# ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:${CLANG_PATH}/lib
# RUN apt-get update -y \
    # && apt-get upgrade -y \
    # && apt-get install -y --no-install-recommends --fix-missing \
    # mesa-utils \
    # && GOOS="$(go env GOOS)" \
    # && GOARCH="$(go env GOARCH)" \
    # && CGO_ENABLED=1 \
    # && CGO_CXXFLAGS="-g -Ofast -march=native" \
    # CGO_FFLAGS="-g -Ofast -march=native" \
    # CGO_LDFLAGS="-g -Ofast -march=native" \
    # GO111MODULE=on \
    # go install \
    # --ldflags "-s -w -linkmode 'external' \
    # -extldflags '-static -fPIC -m64 -pthread -fopenmp -std=c++17 -lstdc++ -lm'" \
    # -a \
    # -tags "cgo netgo" \
    # -trimpath \
    # -installsuffix "cgo netgo" \
    # github.com/remeh/diago \
    # && upx -9 ${GOPATH}/bin/diago

FROM go-base AS hugo
RUN git clone https://github.com/gohugoio/hugo --depth 1 \
    && cd hugo \
    && go install \
    --ldflags "-s -w" --trimpath \
    && upx -9 ${GOPATH}/bin/hugo

FROM go-base AS prototool
RUN GO111MODULE=on go install \
    --ldflags "-s -w" --trimpath \
    github.com/uber/prototool/cmd/prototool@dev \
    && upx -9 ${GOPATH}/bin/prototool

FROM golangci/golangci-lint:latest AS golangci-lint-base
FROM go-base AS golangci-lint
COPY --from=golangci-lint-base /usr/bin/golangci-lint $GOPATH/bin/golangci-lint
RUN upx -9 ${GOPATH}/bin/golangci-lint

FROM go-base AS flamegraph
RUN git clone --depth 1 https://github.com/brendangregg/FlameGraph /tmp/FlameGraph \
    && cp /tmp/FlameGraph/flamegraph.pl ${GOPATH}/bin/ \
    && cp /tmp/FlameGraph/stackcollapse.pl ${GOPATH}/bin/ \
    && cp /tmp/FlameGraph/stackcollapse-go.pl ${GOPATH}/bin/

FROM go-base AS gosec
RUN GO111MODULE=on go install \
    --ldflags "-s -w" --trimpath \
    github.com/securego/gosec/cmd/gosec@latest \
    && upx -9 ${GOPATH}/bin/gosec

# FROM go-base AS k6
# RUN GO111MODULE=on go install \
#     --ldflags "-s -w" --trimpath \
#     github.com/loadimpact/k6@latest \
#     && upx -9 ${GOPATH}/bin/k6

# FROM go-base AS evans
# RUN set -x; cd "$(mktemp -d)" \
#     && OS="$(go env GOOS)" \
#     && ARCH="$(go env GOARCH)" \
#     && NAME="evans" \
#     && ORG="ktr0731" \
#     && REPO="${ORG}/${NAME}" \
#     && GO111MODULE=on go install \
#     --ldflags "-s -w" --trimpath \
#     github.com/ktr0731/evans@latest \
#     && upx -9 ${GOPATH}/bin/evans
#    && EVANS_VERSION="$(curl --silent https://github.com/${REPO}/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
#    && curl -fsSLO "https://github.com/${REPO}/releases/download/${EVANS_VERSION}/${NAME}_${OS}_${ARCH}.tar.gz" \
#    && tar zxf "${NAME}_${OS}_${ARCH}.tar.gz" \
#    && mv ${NAME} ${GOPATH}/bin/${NAME} \
#    && upx -9 ${GOPATH}/bin/${NAME}

FROM go-base AS sqls
RUN GO111MODULE=on go install \
    --ldflags "-s -w" --trimpath \
    github.com/lighttiger2505/sqls@latest \
    && upx -9 ${GOPATH}/bin/sqls

FROM go-base AS vgrun
RUN GO111MODULE=on go install \
    --ldflags "-s -w" --trimpath \
    github.com/vugu/vgrun@latest \
    && upx -9 ${GOPATH}/bin/vgrun

FROM go-base AS vegeta
RUN GO111MODULE=on go install \
    --ldflags "-s -w" --trimpath \
    github.com/tsenart/vegeta@latest \
    && upx -9 ${GOPATH}/bin/vegeta

# FROM go-base AS pulumi
# RUN curl -fsSL https://get.pulumi.com | sh \
#     && mv $HOME/.pulumi/bin/pulumi ${GOPATH}/bin/pulumi \
#     && upx -9 ${GOPATH}/bin/pulumi

FROM go-base AS tinygo
RUN set -x; cd "$(mktemp -d)" \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH | sed 's/arm64/arm/')" \
    && TINYGO_VERSION="$(curl --silent https://github.com/tinygo-org/tinygo/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "https://github.com/tinygo-org/tinygo/releases/download/v${TINYGO_VERSION}/tinygo${TINYGO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && tar zxf "tinygo${TINYGO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && mv tinygo/bin/tinygo ${GOPATH}/bin/tinygo \
    && upx -9 ${GOPATH}/bin/tinygo

FROM go-base AS duf
RUN GO111MODULE=on go install \
    --ldflags "-s -w" --trimpath \
    github.com/muesli/duf@latest \
    && upx -9 ${GOPATH}/bin/duf


FROM go-base AS ruleguard
RUN GO111MODULE=on go install \
    --ldflags "-s -w" --trimpath \
    github.com/quasilyte/go-ruleguard/cmd/ruleguard@latest \
    && upx -9 ${GOPATH}/bin/ruleguard

FROM go-base AS go
RUN upx -9 ${GOROOT}/bin/*

FROM go-base AS go-bins
# COPY --from=act $GOPATH/bin/act $GOPATH/bin/act
# COPY --from=diago $GOPATH/bin/diago $GOPATH/bin/diago
# COPY --from=evans $GOPATH/bin/evans $GOPATH/bin/evans
# COPY --from=grpcurl $GOPATH/bin/grpcurl $GOPATH/bin/grpcurl
# COPY --from=k6 $GOPATH/bin/k6 $GOPATH/bin/k6
# COPY --from=pulumi $GOPATH/bin/pulumi $GOPATH/bin/pulumi
COPY --from=air $GOPATH/bin/air $GOPATH/bin/air
COPY --from=chidley $GOPATH/bin/chidley $GOPATH/bin/chidley
COPY --from=dbmate $GOPATH/bin/dbmate $GOPATH/bin/dbmate
COPY --from=dlv $GOPATH/bin/dlv $GOPATH/bin/dlv
COPY --from=dragon-imports $GOPATH/bin/dragon-imports $GOPATH/bin/dragon-imports
COPY --from=duf $GOPATH/bin/duf $GOPATH/bin/duf
COPY --from=efm $GOPATH/bin/efm-langserver $GOPATH/bin/efm-langserver
COPY --from=errcheck $GOPATH/bin/errcheck $GOPATH/bin/errcheck
COPY --from=fillstruct $GOPATH/bin/fillstruct $GOPATH/bin/fillstruct
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
COPY --from=golint $GOPATH/bin/golint $GOPATH/bin/golint
COPY --from=gomodifytags $GOPATH/bin/gomodifytags $GOPATH/bin/gomodifytags
COPY --from=gopls $GOPATH/bin/gopls $GOPATH/bin/gopls
COPY --from=gorename $GOPATH/bin/gorename $GOPATH/bin/gorename
COPY --from=goreturns $GOPATH/bin/goreturns $GOPATH/bin/goreturns
COPY --from=gosec $GOPATH/bin/gosec $GOPATH/bin/gosec
COPY --from=gotags $GOPATH/bin/gotags $GOPATH/bin/gotags
COPY --from=gotests $GOPATH/bin/gotests $GOPATH/bin/gotests
COPY --from=guru $GOPATH/bin/guru $GOPATH/bin/guru
COPY --from=hub $GOPATH/bin/hub $GOPATH/bin/hub
COPY --from=hugo $GOPATH/bin/hugo $GOPATH/bin/hugo
COPY --from=iferr $GOPATH/bin/iferr $GOPATH/bin/iferr
COPY --from=impl $GOPATH/bin/impl $GOPATH/bin/impl
COPY --from=keyify $GOPATH/bin/keyify $GOPATH/bin/keyify
COPY --from=mockgen $GOPATH/bin/mockgen $GOPATH/bin/mockgen
COPY --from=prototool $GOPATH/bin/prototool $GOPATH/bin/prototool
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
