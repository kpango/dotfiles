FROM golang:1.11-alpine AS go

RUN apk update \
    && apk upgrade \
    && apk add --no-cache \
    git \
    curl \
    wget

RUN go get -v -u github.com/cweill/gotests/... \
    && go get -v -u github.com/golang/dep/... \
    && go get -v -u github.com/gopherjs/gopherjs \
    && go get -v -u github.com/motemen/go-iferr/cmd/goiferr \
    && go get -v -u github.com/pwaller/goimports-update-ignore \
    && go get -v -u github.com/sugyan/ttygif \
    && go get -v -u google.golang.org/grpc \
    && go get -v -u sourcegraph.com/sqs/goreturns

FROM alpine:edge

LABEL maintainer="kpango <i.can.feel.gravity@gmail.com>"

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

COPY --from=go /usr/local/go/bin /usr/local/go/bin
COPY --from=go /go/bin /go/bin

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    curl \
    gcc \
    git \
    linux-headers \
    musl-dev\
    neovim \
    python-dev \
    py-pip \
    python3-dev \
    py3-pip && \
    rm -rf /var/cache/apk/*

RUN pip3 install --upgrade pip neovim

COPY . /root/.config/nvim

WORKDIR /root/.config/nvim/plugged/vim-plug

RUN git clone https://github.com/junegunn/vim-plug.git /root/.config/nvim/plugged/vim-plug/autoload \
    && nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall
    # && nvim main.go +GoInstall +GoInstallBinaries +GoUpdateBinaries +qall 

ENTRYPOINT ["nvim"]
