FROM golang:1.11-alpine AS go

RUN apk update \
    && apk upgrade \
    && apk add --no-cache \
    git \
    curl \
    wget

RUN go get -v -u github.com/alecthomas/gometalinter \
    github.com/cweill/gotests/... \
    github.com/davidrjenni/reftools/cmd/fillstruct \
    github.com/derekparker/delve/cmd/dlv \
    github.com/dominikh/go-tools/cmd/keyify \
    github.com/fatih/gomodifytags \
    github.com/fatih/motion \
    github.com/golang/dep/... \
    github.com/gopherjs/gopherjs \
    github.com/josharian/impl \
    github.com/jstemmer/gotags \
    github.com/kisielk/errcheck \
    github.com/klauspost/asmfmt/cmd/asmfmt \
    github.com/koron/iferr \
    github.com/nsf/gocode \
    github.com/motemen/ghq \
    github.com/motemen/go-iferr/cmd/goiferr \
    github.com/pwaller/goimports-update-ignore \
    github.com/rogpeppe/godef \
    github.com/sugyan/ttygif \
    github.com/zmb3/gogetdoc \
    golang.org/x/lint/golint \
    golang.org/x/tools/cmd/goimports \
    golang.org/x/tools/cmd/gorename \
    golang.org/x/tools/cmd/guru \
    google.golang.org/grpc \
    honnef.co/go/tools/cmd/keyify \
    sourcegraph.com/sqs/goreturns \
    && gometalinter -i

FROM kpango/rust-musl-builder:latest AS rust

RUN cargo install --force ripgrep \
    && cargo install --force --no-default-features --git https://github.com/sharkdp/fd \
    && cargo install --force --no-default-features exa
    && cargo install --force --no-default-features bat

FROM docker:latest AS docker

FROM alpine:edge

LABEL maintainer="kpango <i.can.feel.gravity@gmail.com>"

ENV HOME /root
ENV GOPATH /go
ENV GOROOT /usr/local/go
ENV CARGO_PATH /usr/local/cargo
ENV PATH $GOPATH/bin:/usr/local/go/bin:$CARGO_PATH/bin:$PATH
ENV NVIM_HOME $HOME/.config/nvim
ENV LIBRARY_PATH /usr/local/lib:$LIBRARY_PATH
ENV ZPLUG_HOME $HOME/.zplug;

COPY --from=go /usr/local/go/bin $GOROOT/bin
COPY --from=go /usr/local/go/src $GOROOT/src
COPY --from=go /usr/local/go/lib $GOROOT/lib
COPY --from=go /usr/local/go/pkg $GOROOT/pkg
COPY --from=go /usr/local/go/misc $GOROOT/misc
COPY --from=go /go/bin $GOPATH/bin
COPY --from=go /go/src/github.com/nsf/gocode/vim $GOROOT/misc/vim
COPY --from=rust /home/rust/.cargo/bin /usr/local/cargo/bin
COPY --from=docker /usr/local/bin/docker /usr/bin/docker
COPY --from=docker /usr/local/bin/docker-containerd /usr/bin/docker-containerd
COPY --from=docker /usr/local/bin/docker-containerd-ctr /usr/bin/docker-containerd-ctr
COPY --from=docker /usr/local/bin/docker-containerd-shim /usr/bin/docker-containerd-shim
COPY --from=docker /usr/local/bin/docker-entrypoint.sh /usr/bin/docker-entrypoint
COPY --from=docker /usr/local/bin/docker-init /usr/bin/docker-init
COPY --from=docker /usr/local/bin/docker-proxy /usr/bin/docker-proxy
COPY --from=docker /usr/local/bin/docker-runc /usr/bin/docker-runc
COPY --from=docker /usr/local/bin/dockerd /usr/bin/dockerd
COPY --from=docker /usr/local/bin/modprobe /usr/bin/modprobe

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

WORKDIR /tmp
RUN apk update \
    && apk upgrade \
    && apk --update add --no-cache \
    make \
    curl \
    gcc \
    git \
    linux-headers \
    musl-dev\
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
    ncurses \
    && rm -rf /var/cache/apk/*

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && mv ./kubectl /usr/bin/kubectl \
    && chmod +x /usr/bin/kubectl \
    && kubectl version --client \
    && git clone https://github.com/ahmetb/kubectx /opt/kubectx \
    && ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx \
    && ln -s /opt/kubectx/kubens /usr/local/bin/kubens

RUN pip3 install --upgrade pip neovim \
    && pip2 install --upgrade pip neovim \
    && pip install --upgrade pip neovim

RUN gem install neovim --no-ri --no-rdoc
# RUN npm install -g neovim
RUN gocode set autobuild true \
    && gocode set lib-path $GOPATH/pkg/$GOOS\_$GOARCH/ \
    && gocode set propose-builtins true \
    && gocode set unimported-packages true

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
    && nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall \
    && git clone https://github.com/zplug/zplug $ZPLUG_HOME

WORKDIR /go/src

ENTRYPOINT ["docker-entrypoint"]
CMD ["zsh"]
