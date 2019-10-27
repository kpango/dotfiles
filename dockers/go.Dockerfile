FROM golang:1.13-alpine AS go-base

RUN apk update \
    && apk upgrade \
    && apk add --no-cache \
    git \
    curl \
    gcc \
    musl-dev \
    wget \
    upx

FROM go-base AS default

RUN GO111MODULE=on go get -u  \
    github.com/ChimeraCoder/gojson/gojson \
    github.com/a8m/syncmap \
    github.com/cweill/gotests/gotests \
    github.com/davidrjenni/reftools/cmd/fillstruct \
    github.com/fatih/gomodifytags \
    github.com/gnewton/chidley \
    github.com/go-delve/delve/cmd/dlv \
    github.com/josharian/impl \
    github.com/jstemmer/gotags \
    github.com/kisielk/errcheck \
    github.com/koron/iferr \
    github.com/monochromegane/dragon-imports/cmd/dragon-imports \
    github.com/motemen/ghq \
    github.com/nsf/gocode \
    github.com/pwaller/goimports-update-ignore \
    github.com/rogpeppe/godef \
    github.com/uber/prototool/cmd/prototool \
    golang.org/x/lint/golint \
    golang.org/x/tools/cmd/goimports \
    golang.org/x/tools/cmd/gopls \
    golang.org/x/tools/cmd/gorename \
    golang.org/x/tools/cmd/guru \
    google.golang.org/grpc \
    honnef.co/go/tools/cmd/keyify \
    sourcegraph.com/sqs/goreturns

FROM go-base AS go-module-off-base
RUN GO111MODULE=off go get \
    github.com/mattn/efm-langserver \
    github.com/gohugoio/hugo \
    github.com/golangci/golangci-lint/cmd/golangci-lint \

FROM go-module-off-base AS hugo
RUN cd $GOPATH/src/github.com/gohugoio/hugo \
    && GO111MODULE=on go build -o $GOPATH/bin/hugo main.go

FROM go-module-off-base AS efm
RUN cd $GOPATH/src/github.com/mattn/efm-langserver \
    && GO111MODULE=on go build -o $GOPATH/bin/efm-langserver

FROM golangci/golangci-lint:latest AS golangci-lint

FROM go-base AS go

COPY --from=default $GOPATH/bin/ $GOPATH/bin
COPY --from=hugo $GOPATH/bin/hugo $GOPATH/bin/hugo
COPY --from=efm $GOPATH/bin/efm-langserver $GOPATH/bin/efm-langserver
COPY --from=golangci-lint /usr/bin/golangci-lint $GOPATH/bin/golangci-lint

RUN upx -9 ${GOPATH}/bin/* \
    \
    && git clone https://github.com/brendangregg/FlameGraph /tmp/FlameGraph \
    && cp /tmp/FlameGraph/flamegraph.pl /go/bin/ \
    && cp /tmp/FlameGraph/stackcollapse.pl /go/bin/ \
    && cp /tmp/FlameGraph/stackcollapse-go.pl /go/bin/

# FROM scratch
# ENV GOROOT /usr/local/go
# COPY --from=go $GOROOT/bin $GOROOT/bin
# COPY --from=go $GOROOT/src $GOROOT/src
# COPY --from=go $GOROOT/lib $GOROOT/lib
# COPY --from=go $GOROOT/pkg $GOROOT/pkg
# COPY --from=go $GOROOT/misc $GOROOT/misc
# COPY --from=go /go/bin $GOPATH/bin
