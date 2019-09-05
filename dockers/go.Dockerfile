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

# RUN --mount=type=cache,target=/root/.cache/go-build \
#     go get -v -u \
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
    github.com/mattn/efm-langserver \
    github.com/motemen/ghq \
    github.com/nsf/gocode \
    github.com/pwaller/goimports-update-ignore \
    github.com/rogpeppe/godef \
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
    github.com/gohugoio/hugo \
    github.com/golangci/golangci-lint/cmd/golangci-lint \
    github.com/orisano/dlayer \
    # github.com/orisano/minid \
    github.com/saibing/bingo

FROM go-module-off-base AS hugo
RUN cd $GOPATH/src/github.com/gohugoio/hugo \
    && GO111MODULE=on go build -o $GOPATH/bin/hugo main.go

FROM go-module-off-base AS bingo
RUN cd $GOPATH/src/github.com/saibing/bingo \
    && GO111MODULE=on go build -o $GOPATH/bin/bingo main.go

FROM go-module-off-base AS dlayer
RUN cd $GOPATH/src/github.com/orisano/dlayer \
    && GO111MODULE=on go build -o $GOPATH/bin/dlayer main.go

# FROM go-module-off-base AS minid
# RUN cd $GOPATH/src/github.com/orisano/minid \
#     && GO111MODULE=on go build -o $GOPATH/bin/minid main.go

FROM golangci/golangci-lint:latest AS golangci-lint
FROM wagoodman/dive:latest AS dive
FROM goodwithtech/dockle:latest AS dockle
FROM aquasec/trivy:latest AS trivy

FROM go-base AS go

COPy --from=default $GOPATH/bin/ $GOPATH/bin
COPy --from=hugo $GOPATH/bin/hugo $GOPATH/bin/hugo
COPy --from=dlayer $GOPATH/bin/dlayer $GOPATH/bin/dlayer
COPy --from=bingo $GOPATH/bin/bingo $GOPATH/bin/bingo
# COPy --from=minid $GOPATH/bin/minid $GOPATH/bin/minid
COPy --from=dive /dive $GOPATH/bin/dive
COPy --from=dockle /usr/local/bin/dockle $GOPATH/bin/dockle
COPy --from=golangci-lint /usr/bin/golangci-lint $GOPATH/bin/golangci-lint

RUN upx --best --ultra-brute ${GOPATH}/bin/* \
    \
    && git clone https://github.com/brendangregg/FlameGraph /tmp/FlameGraph \
    && cp /tmp/FlameGraph/flamegraph.pl /go/bin/ \
    && cp /tmp/FlameGraph/stackcollapse.pl /go/bin/ \
    && cp /tmp/FlameGraph/stackcollapse-go.pl /go/bin/

COPy --from=trivy /usr/local/bin/trivy $GOPATH/bin/trivy
