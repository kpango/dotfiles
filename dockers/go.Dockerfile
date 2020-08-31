FROM kpango/dev-base:latest AS go-base

ENV GO_VERSION 1.15
ENV GO111MODULE on
ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ENV LANG en_US.UTF-8
ENV GOROOT /opt/go
ENV GOPATH /go
ENV GOFLAGS "-ldflags=-w -ldflags=-s"

WORKDIR /opt
RUN curl -sSL -O "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" \
    && tar zxf "go${GO_VERSION}.linux-amd64.tar.gz" \
    && rm "go${GO_VERSION}.linux-amd64.tar.gz" \
    && ln -s /opt/go/bin/go /usr/bin/ \
    && mkdir -p ${GOPATH}/bin

FROM go-base AS gojson
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/ChimeraCoder/gojson/gojson \
    && upx -9 ${GOPATH}/bin/gojson

FROM go-base AS syncmap
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/a8m/syncmap \
    && upx -9 ${GOPATH}/bin/syncmap

FROM go-base AS gotests
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/cweill/gotests/gotests \
    && upx -9 ${GOPATH}/bin/gotests

FROM go-base AS fillstruct
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/davidrjenni/reftools/cmd/fillstruct \
    && upx -9 ${GOPATH}/bin/fillstruct

FROM go-base AS gomodifytags
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/fatih/gomodifytags \
    && upx -9 ${GOPATH}/bin/gomodifytags

FROM go-base AS chidley
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/gnewton/chidley \
    && upx -9 ${GOPATH}/bin/chidley

FROM go-base AS dlv
RUN git clone https://github.com/go-delve/delve.git $GOPATH/src/github.com/go-delve/delve \
    && cd $GOPATH/src/github.com/go-delve/delve \
    && make install \
    && upx -9 ${GOPATH}/bin/dlv
# RUN GO111MODULE=on go get -u  \
#     --ldflags "-s -w" --trimpath \
#     github.com/go-delve/delve/cmd/dlv \
#     && upx -9 ${GOPATH}/bin/dlv

FROM go-base AS hub
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/github/hub \
    && upx -9 ${GOPATH}/bin/hub

FROM go-base AS impl
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/josharian/impl \
    && upx -9 ${GOPATH}/bin/impl

FROM go-base AS gotags
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/jstemmer/gotags \
    && upx -9 ${GOPATH}/bin/gotags

FROM go-base AS errcheck
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/kisielk/errcheck \
    && upx -9 ${GOPATH}/bin/errcheck

FROM go-base AS iferr
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/koron/iferr \
    && upx -9 ${GOPATH}/bin/iferr

FROM go-base AS dragon-imports
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/rerost/dragon-imports/cmd/dragon-imports \
    && upx -9 ${GOPATH}/bin/dragon-imports

FROM go-base AS grpcurl
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/fullstorydev/grpcurl/cmd/grpcurl \
    && upx -9 ${GOPATH}/bin/grpcurl

FROM go-base AS ghq
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/x-motemen/ghq \
    && upx -9 ${GOPATH}/bin/ghq

FROM go-base AS gocode
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/nsf/gocode \
    && upx -9 ${GOPATH}/bin/gocode

FROM go-base AS goimports-update-ignore
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/pwaller/goimports-update-ignore \
    && upx -9 ${GOPATH}/bin/goimports-update-ignore

FROM go-base AS godef
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/rogpeppe/godef \
    && upx -9 ${GOPATH}/bin/godef

FROM go-base AS efm
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/mattn/efm-langserver \
    && upx -9 ${GOPATH}/bin/efm-langserver

FROM go-base AS golint
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/lint/golint \
    && upx -9 ${GOPATH}/bin/golint

FROM go-base AS goimports
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/cmd/goimports \
    && upx -9 ${GOPATH}/bin/goimports

FROM go-base AS ghz
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    github.com/bojand/ghz/cmd/ghz \
    && upx -9 ${GOPATH}/bin/ghz

FROM go-base AS gopls
RUN GO111MODULE=on go get \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/gopls@latest \
    && upx -9 ${GOPATH}/bin/gopls

FROM go-base AS gorename
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/cmd/gorename \
    && upx -9 ${GOPATH}/bin/gorename

FROM go-base AS guru
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    golang.org/x/tools/cmd/guru \
    && upx -9 ${GOPATH}/bin/guru

FROM go-base AS keyify
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    honnef.co/go/tools/cmd/keyify \
    && upx -9 ${GOPATH}/bin/keyify

FROM go-base AS goreturns
RUN GO111MODULE=on go get -u  \
    --ldflags "-s -w" --trimpath \
    sourcegraph.com/sqs/goreturns \
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
    # go get -u \
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
RUN GO111MODULE=on go get -u \
    --ldflags "-s -w" --trimpath \
    github.com/uber/prototool/cmd/prototool@dev \
    && upx -9 ${GOPATH}/bin/prototool

FROM golangci/golangci-lint:latest AS golangci-lint-base
FROM go-base AS golangci-lint
COPY --from=golangci-lint-base /usr/bin/golangci-lint $GOPATH/bin/golangci-lint
RUN upx -9 ${GOPATH}/bin/golangci-lint

FROM go-base AS flamegraph
RUN git clone https://github.com/brendangregg/FlameGraph /tmp/FlameGraph \
    && cp /tmp/FlameGraph/flamegraph.pl ${GOPATH}/bin/ \
    && cp /tmp/FlameGraph/stackcollapse.pl ${GOPATH}/bin/ \
    && cp /tmp/FlameGraph/stackcollapse-go.pl ${GOPATH}/bin/

FROM go-base AS gosec
RUN GO111MODULE=on go get -u \
    --ldflags "-s -w" --trimpath \
    github.com/securego/gosec/cmd/gosec \
    && upx -9 ${GOPATH}/bin/gosec

FROM go-base AS evans
RUN GO111MODULE=on go get -u \
    --ldflags "-s -w" --trimpath \
    github.com/ktr0731/evans \
    && upx -9 ${GOPATH}/bin/evans

FROM go-base AS sqls
RUN GO111MODULE=on go get -u \
    --ldflags "-s -w" --trimpath \
    github.com/lighttiger2505/sqls \
    && upx -9 ${GOPATH}/bin/sqls

FROM go-base AS vgrun
RUN GO111MODULE=on go get -u \
    --ldflags "-s -w" --trimpath \
    github.com/vugu/vgrun \
    && upx -9 ${GOPATH}/bin/vgrun

FROM go-base AS vegeta
RUN GO111MODULE=on go get -u \
    --ldflags "-s -w" --trimpath \
    github.com/tsenart/vegeta \
    && upx -9 ${GOPATH}/bin/vegeta


FROM go-base AS pulumi
# RUN PULUMI_VERSION="$(curl --silent https://github.com/pulumi/pulumi/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
RUN curl -fsSL https://get.pulumi.com | sh \
    && mv $HOME/.pulumi/bin/pulumi ${GOPATH}/bin/pulumi \
    && upx -9 ${GOPATH}/bin/pulumi

FROM go-base AS tinygo
RUN set -x; cd "$(mktemp -d)" \
    && OS="$(go env GOOS)" \
    && ARCH="$(go env GOARCH)" \
    && TINYGO_VERSION="$(curl --silent https://github.com/tinygo-org/tinygo/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "https://github.com/tinygo-org/tinygo/releases/download/v${TINYGO_VERSION}/tinygo${TINYGO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && tar zxf "tinygo${TINYGO_VERSION}.${OS}-${ARCH}.tar.gz" \
    && mv tinygo/bin/tinygo ${GOPATH}/bin/tinygo \
    && upx -9 ${GOPATH}/bin/tinygo

FROM go-base AS go
RUN upx -9 ${GOROOT}/bin/*

FROM go-base AS go-libs
# COPY --from=diago $GOPATH/bin/diago $GOPATH/bin/diago
COPY --from=chidley $GOPATH/bin/chidley $GOPATH/bin/chidley
COPY --from=dlv $GOPATH/bin/dlv $GOPATH/bin/dlv
COPY --from=dragon-imports $GOPATH/bin/dragon-imports $GOPATH/bin/dragon-imports
COPY --from=efm $GOPATH/bin/efm-langserver $GOPATH/bin/efm-langserver
COPY --from=errcheck $GOPATH/bin/errcheck $GOPATH/bin/errcheck
COPY --from=evans $GOPATH/bin/evans $GOPATH/bin/evans
COPY --from=fillstruct $GOPATH/bin/fillstruct $GOPATH/bin/fillstruct
COPY --from=flamegraph $GOPATH/bin/flamegraph.pl $GOPATH/bin/flamegraph.pl
COPY --from=flamegraph $GOPATH/bin/stackcollapse-go.pl $GOPATH/bin/stackcollapse-go.pl
COPY --from=flamegraph $GOPATH/bin/stackcollapse.pl $GOPATH/bin/stackcollapse.pl
COPY --from=ghq $GOPATH/bin/ghq $GOPATH/bin/ghq
COPY --from=ghz $GOPATH/bin/ghz $GOPATH/bin/ghz
COPY --from=gocode $GOPATH/bin/gocode $GOPATH/bin/gocode
COPY --from=godef $GOPATH/bin/godef $GOPATH/bin/godef
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
COPY --from=grpcurl $GOPATH/bin/grpcurl $GOPATH/bin/grpcurl
COPY --from=guru $GOPATH/bin/guru $GOPATH/bin/guru
COPY --from=hub $GOPATH/bin/hub $GOPATH/bin/hub
COPY --from=hugo $GOPATH/bin/hugo $GOPATH/bin/hugo
COPY --from=iferr $GOPATH/bin/iferr $GOPATH/bin/iferr
COPY --from=impl $GOPATH/bin/impl $GOPATH/bin/impl
COPY --from=keyify $GOPATH/bin/keyify $GOPATH/bin/keyify
COPY --from=prototool $GOPATH/bin/prototool $GOPATH/bin/prototool
COPY --from=pulumi $GOPATH/bin/pulumi $GOPATH/bin/pulumi
COPY --from=sqls $GOPATH/bin/sqls $GOPATH/bin/sqls
COPY --from=syncmap $GOPATH/bin/syncmap $GOPATH/bin/syncmap
COPY --from=tinygo $GOPATH/bin/tinygo $GOPATH/bin/tinygo
COPY --from=vgrun $GOPATH/bin/vgrun $GOPATH/bin/vgrun
COPY --from=vegeta $GOPATH/bin/vegeta $GOPATH/bin/vegeta

FROM scratch
ENV GOROOT /opt/go
ENV GOPATH /go
COPY --from=go $GOROOT/bin $GOROOT/bin
COPY --from=go $GOROOT/src $GOROOT/src
COPY --from=go $GOROOT/lib $GOROOT/lib
COPY --from=go $GOROOT/pkg $GOROOT/pkg
COPY --from=go $GOROOT/misc $GOROOT/misc
COPY --from=go-libs $GOPATH/bin $GOPATH/bin
