FROM golang:1.11-alpine AS go

RUN apk update \
    && apk upgrade \
    && apk add --no-cache \
    git \
    curl \
    gcc \
    musl-dev \
    wget

# RUN --mount=target=/root/.cache,type=cache \
RUN go get -v -u github.com/alecthomas/gometalinter \
    github.com/cweill/gotests/... \
    github.com/davidrjenni/reftools/cmd/fillstruct \
    github.com/derekparker/delve/cmd/dlv \
    github.com/dominikh/go-tools/cmd/keyify \
    github.com/fatih/gomodifytags \
    github.com/fatih/motion \
    github.com/gohugoio/hugo \
    github.com/golang/dep/... \
    github.com/gopherjs/gopherjs \
    github.com/josharian/impl \
    github.com/jstemmer/gotags \
    github.com/kisielk/errcheck \
    github.com/klauspost/asmfmt/cmd/asmfmt \
    github.com/koron/iferr \
    github.com/motemen/ghq \
    github.com/motemen/go-iferr/cmd/goiferr \
    github.com/nsf/gocode \
    github.com/pwaller/goimports-update-ignore \
    github.com/rogpeppe/godef \
    github.com/sugyan/ttygif \
    github.com/zmb3/gogetdoc \
    golang.org/x/lint/golint \
    golang.org/x/tools/cmd/goimports \
    golang.org/x/tools/cmd/golsp \
    golang.org/x/tools/cmd/gorename \
    golang.org/x/tools/cmd/guru \
    google.golang.org/grpc \
    honnef.co/go/tools/cmd/keyify \
    sigs.k8s.io/kustomize \
    sourcegraph.com/sqs/goreturns \
    && gometalinter -i \
    && git clone https://github.com/saibing/bingo.git \
    && cd bingo \
    && GO111MODULE=on go install

FROM kpango/rust-musl-builder:latest AS rust

RUN cargo install --force ripgrep \
    && cargo install --force --no-default-features --git https://github.com/sharkdp/fd \
    && cargo install --force --no-default-features exa \
    && cargo install --force --no-default-features bat

FROM docker:18.09-dind AS docker

FROM google/cloud-sdk:alpine AS gcloud

RUN gcloud config set core/disable_usage_reporting true \
    && gcloud config set component_manager/disable_update_check true \
    && gcloud config set metrics/environment github_docker_image \
    && gcloud --version

FROM nimlang/nim:latest-alpine AS nim

# FROM node:11-alpine AS node

# RUN npm config set user  root \
#     && npm install -g neovim resume-cli

# FROM python:3.7-alpine AS python3

# RUN apk add --no-cache --virtual .build-deps gcc musl-dev
# RUN pip3 install --upgrade pip neovim
# RUN apk del .build-deps gcc musl-dev

# FROM python:2.7-alpine AS python2

# RUN apk add --no-cache --virtual .build-deps gcc musl-dev
# RUN pip2 install --upgrade pip neovim
# RUN apk del .build-deps gcc musl-dev

# FROM ruby:alpine AS ruby
#
# RUN apk add --no-cache --virtual .build-deps gcc make musl-dev
# RUN gem install neovim -no-ri-no-rdoc
# RUN apk del .build-deps gcc musl-dev

FROM google/dart:dev AS dart

FROM alpine:edge AS base

FROM base AS kube

RUN apk update \
    && apk upgrade \
    && apk --update add --no-cache \
    make \
    curl \
    gcc \
    openssl \
    bash \
    git

RUN set -x; cd "$(mktemp -d)" \
    && curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" \
    && mv ./kubectl /usr/local/bin/kubectl \
    && chmod a+x /usr/local/bin/kubectl \
    && kubectl version --client \
    && curl "https://raw.githubusercontent.com/helm/helm/master/scripts/get" | bash \
    && git clone "https://github.com/ahmetb/kubectx" /opt/kubectx \
    && ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx \
    && ln -s /opt/kubectx/kubens /usr/local/bin/kubens \
    && curl -fsSLO "https://storage.googleapis.com/krew/v0.2.1/krew.{tar.gz,yaml}" \
    && tar zxvf krew.tar.gz \
    && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" install --manifest=krew.yaml --archive=krew.tar.gz \
    && ls /root/.krew \
    && ls /root/.krew/bin

FROM base AS env

ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/usr/x86_64-alpine-linux-musl/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib

RUN mkdir "/etc/ld.so.conf.d" \
    && echo $'/lib\n\
/lib64\n\
/var/lib\n\
/usr/lib\n\
/usr/local/lib\n\
/usr/x86_64-alpine-linux-musl/lib\n\
/usr/local/go/lib\n\
/usr/lib/dart/lib\n\
/usr/lib/node_modules/lib\n\
/google-cloud-sdk/lib' > /etc/ld.so.conf.d/usr-local-lib.conf \
    && echo $(ldconfig) \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && apk update \
    && apk upgrade \
    && apk --update add --no-cache \
    make \
    cmake \
    curl \
    gcc \
    g++ \
    git \
    diffutils \
    linux-headers \
    openssl \
    openssl-dev \
    musl-dev \
    neovim \
    python-dev \
    py-pip \
    python3-dev \
    py3-pip \
    nodejs \
    npm \
    ruby-dev \
    tmux \
    zsh \
    bash \
    xclip \
    perl \
    less \
    # ncurses \
    tig \
    tzdata \
    jq \
    ctags \
    && rm -rf /var/cache/apk/* \
    && pip2 install --upgrade pip neovim python-language-server \
    && pip3 install --upgrade pip neovim ranger-fm thefuck httpie python-language-server \
    && gem install neovim -N \
    && npm config set user root \
    && npm install -g neovim resume-cli dockerfile-language-server-nodejs typescript typescript-language-server \
    && curl -Lo ngt.tar.gz https://github.com/yahoojapan/NGT/archive/v1.5.1.tar.gz \
    && tar zxf ngt.tar.gz -C /tmp \
    && rm -rf ngt.tar.gz \
    && cd /tmp/NGT-1.5.1 \
    && cmake . \
    && make -j -C /tmp/NGT-1.5.1 \
    && make install -C /tmp/NGT-1.5.1 \
    && rm -rf /tmp/NGT-1.5.1

FROM env

LABEL maintainer="kpango <i.can.feel.gravity@gmail.com>"

ENV TZ Asia/Tokyo
ENV HOME /root
ENV GOPATH /go
ENV GOROOT /usr/local/go
ENV GCLOUD_PATH /google-cloud-sdk
ENV CARGO_PATH /usr/local/cargo
ENV DART_PATH /usr/lib/dart
ENV PATH $GOPATH/bin:/usr/local/go/bin:$CARGO_PATH/bin:$DART_PATH/bin:$GCLOUD_PATH/bin:$PATH
ENV NVIM_HOME $HOME/.config/nvim
ENV LIBRARY_PATH /usr/local/lib:$LIBRARY_PATH
ENV ZPLUG_HOME $HOME/.zplug;

# COPY --from=python3 /usr/local /usr/local
# COPY --from=python2 /usr/local /usr/local

# COPY --from=node /usr/local/bin/node /usr/bin/node
# COPY --from=node /usr/local/bin/npm /usr/bin/npm
# COPY --from=node /usr/local/bin/yarn /usr/bin/yarn
# COPY --from=node /usr/local/bin/neovim-node-host /usr/bin/neovim-node-host
# COPY --from=node /usr/local/bin/resume /usr/bin/resume
# COPY --from=node /usr/local/lib/node_modules /usr/lib/node_modules

# COPY --from=ruby /usr/local/bin/ruby /usr/bin/ruby
# COPY --from=ruby /usr/local/bin/gem /usr/bin/gem
# COPY --from=ruby /usr/local/lib/ruby /usr/lib/ruby
# COPY --from=ruby /usr/local/lib/libruby* /usr/lib/
# COPY --from=ruby /usr/local/bundle /usr/bundle

COPY --from=docker /usr/local/bin/containerd /usr/bin/docker-containerd
COPY --from=docker /usr/local/bin/containerd-shim /usr/bin/docker-containerd-shim
COPY --from=docker /usr/local/bin/ctr /usr/bin/docker-containerd-ctr
COPY --from=docker /usr/local/bin/dind /usr/bin/dind
COPY --from=docker /usr/local/bin/docker /usr/bin/docker
COPY --from=docker /usr/local/bin/docker-entrypoint.sh /usr/bin/docker-entrypoint
COPY --from=docker /usr/local/bin/docker-init /usr/bin/docker-init
COPY --from=docker /usr/local/bin/docker-proxy /usr/bin/docker-proxy
COPY --from=docker /usr/local/bin/dockerd /usr/bin/dockerd
COPY --from=docker /usr/local/bin/modprobe /usr/bin/modprobe
COPY --from=docker /usr/local/bin/runc /usr/bin/docker-runc

COPY --from=kube /usr/local/bin/kubectl /usr/bin/kubectl
COPY --from=kube /usr/local/bin/kubectx /usr/bin/kubectx
COPY --from=kube /usr/local/bin/kubens /usr/bin/kubens
COPY --from=kube /usr/local/bin/helm /usr/bin/helm
COPY --from=kube /root/.krew/bin /usr/bin/

COPY --from=gcloud /google-cloud-sdk /google-cloud-sdk
COPY --from=gcloud /root/.config/gcloud /root/.config/gcloud

COPY --from=nim /bin/nim /usr/local/bin/nim
COPY --from=nim /bin/nimble /usr/local/bin/nimble
COPY --from=nim /bin/nimsuggest /usr/local/bin/nimsuggest
COPY --from=nim /nim /nim

COPY --from=dart /usr/lib/dart/bin /usr/lib/dart/bin
COPY --from=dart /usr/lib/dart/lib /usr/lib/dart/lib
COPY --from=dart /usr/lib/dart/include /usr/lib/dart/include

COPY --from=go /usr/local/go/bin $GOROOT/bin
COPY --from=go /usr/local/go/src $GOROOT/src
COPY --from=go /usr/local/go/lib $GOROOT/lib
COPY --from=go /usr/local/go/pkg $GOROOT/pkg
COPY --from=go /usr/local/go/misc $GOROOT/misc
COPY --from=go /go/bin $GOPATH/bin
# COPY --from=go /go/src/github.com/nsf/gocode/vim $GOROOT/misc/vim

COPY --from=rust /home/rust/.cargo/bin /usr/local/cargo/bin

COPY init.vim $NVIM_HOME/init.vim
COPY monokai.vim $NVIM_HOME/colors/monokai.vim
COPY zshrc $HOME/.zshrc
COPY tmux.conf $HOME/.tmux.conf
COPY gitignore $HOME/.gitignore
COPY gitconfig $HOME/.gitconfig
COPY gitattributes $HOME/.gitattributes

ENV SHELL /bin/zsh

RUN  ["/bin/zsh", "-c", "source ~/.zshrc"]

WORKDIR $NVIM_HOME/plugged/vim-plug

RUN rm -rf /root/.config/nvim/plugged/vim-plug/autoload \
    && git clone https://github.com/junegunn/vim-plug.git /root/.config/nvim/plugged/vim-plug/autoload \
    && nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +GoInstallBinaries +qall main.go \
    && git clone https://github.com/zplug/zplug $ZPLUG_HOME

WORKDIR /go/src

ENTRYPOINT ["docker-entrypoint"]
CMD ["zsh"]
