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
    github.com/garyburd/go-explorer/src/getool \
    github.com/golang/dep/... \
    github.com/golang/lint/golint \
    github.com/gopherjs/gopherjs \
    github.com/josharian/impl \
    github.com/jstemmer/gotags \
    github.com/kisielk/errcheck \
    github.com/klauspost/asmfmt/cmd/asmfmt \
    github.com/koron/iferr \
    github.com/nsf/gocode \
    github.com/motemen/go-iferr/cmd/goiferr \
    github.com/pwaller/goimports-update-ignore \
    github.com/rogpeppe/godef \
    github.com/sugyan/ttygif \
    github.com/zmb3/gogetdoc \
    golang.org/x/tools/cmd/goimports \
    golang.org/x/tools/cmd/gorename \
    golang.org/x/tools/cmd/guru \
    google.golang.org/grpc \
    honnef.co/go/tools/cmd/keyify \
    sourcegraph.com/sqs/goreturns \
    && gometalinter -i

FROM alpine:edge

LABEL maintainer="kpango <i.can.feel.gravity@gmail.com>"

ENV HOME /root
ENV GOPATH /go
ENV GOROOT /usr/local/go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH
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

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk update \
    && apk upgrade \
    && apk add --no-cache \
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
    xclip \
    perl \
    && rm -rf /var/cache/apk/*

RUN pip3 install --upgrade pip neovim \
    && pip2 install --upgrade pip neovim \
    && pip install --upgrade pip neovim

RUN gem install neovim --no-ri --no-rdoc
RUN npm install -g neovim
RUN gocode set autobuild true \
    && gocode set lib-path $GOPATH/pkg/$GOOS\_$GOARCH/ \
    && gocode set propose-builtins true \
    && gocode set unimported-packages true

COPY init.vim $NVIM_HOME/init.vim
COPY monokai.vim $NVIM_HOME/colors/monokai.vim
COPY zshrc $HOME/.zshrc
COPY tmux.conf $HOME/.tmux.conf

WORKDIR $NVIM_HOME/plugged/vim-plug

RUN git clone https://github.com/junegunn/vim-plug.git /root/.config/nvim/plugged/vim-plug/autoload \
    && nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall \
    && git clone https://github.com/zplug/zplug $ZPLUG_HOME

WORKDIR /go/src

ENTRYPOINT ["zsh"]
