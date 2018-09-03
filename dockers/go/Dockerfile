FROM golang:1.11-alpine AS go

RUN apk update \
    && apk upgrade \
    && apk add --no-cache \
    git \
    curl \
    wget

RUN go get -v -u github.com/alecthomas/gometalinter \
    && go get -v -u github.com/cweill/gotests/... \
    && go get -v -u github.com/davidrjenni/reftools/cmd/fillstruct \
    && go get -v -u github.com/derekparker/delve/cmd/dlv \
    && go get -v -u github.com/dominikh/go-tools/cmd/keyify \
    && go get -v -u github.com/fatih/gomodifytags \
    && go get -v -u github.com/fatih/motion \
    && go get -v -u github.com/garyburd/go-explorer/src/getool \
    && go get -v -u github.com/golang/dep/... \
    && go get -v -u github.com/golang/lint/golint \
    && go get -v -u github.com/gopherjs/gopherjs \
    && go get -v -u github.com/josharian/impl \
    && go get -v -u github.com/jstemmer/gotags \
    && go get -v -u github.com/kisielk/errcheck \
    && go get -v -u github.com/klauspost/asmfmt/cmd/asmfmt \
    && go get -v -u github.com/koron/iferr \
    && go get -v -u github.com/mdempsky/gocode \
    && go get -v -u github.com/motemen/go-iferr/cmd/goiferr \
    && go get -v -u github.com/pwaller/goimports-update-ignore \
    && go get -v -u github.com/rogpeppe/godef \
    && go get -v -u github.com/sugyan/ttygif \
    && go get -v -u github.com/zmb3/gogetdoc \
    && go get -v -u golang.org/x/tools/cmd/goimports \
    && go get -v -u golang.org/x/tools/cmd/gorename \
    && go get -v -u golang.org/x/tools/cmd/guru \
    && go get -v -u google.golang.org/grpc \
    && go get -v -u honnef.co/go/tools/cmd/keyify \
    && go get -v -u sourcegraph.com/sqs/goreturns


FROM alpine:edge

LABEL maintainer="kpango <i.can.feel.gravity@gmail.com>"

ENV HOME /root
ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH
ENV NVIM_HOME $HOME/.config/nvim
ENV LIBRARY_PATH /usr/local/lib:$LIBRARY_PATH
ENV ZPLUG_HOME $HOME/.zplug;

COPY --from=go /usr/local/go/bin /usr/local/go/bin
COPY --from=go /usr/local/go/src /usr/local/go/src
COPY --from=go /go/bin /go/bin

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

COPY init.vim /root/.config/nvim/init.vim
COPY monokai.vim /root/.config/nvim/colors/monokai.vim
COPY zshrc /root/.zshrc
COPY tmux.conf /root/.tmux.conf

WORKDIR /root/.config/nvim/plugged/vim-plug

RUN git clone https://github.com/junegunn/vim-plug.git /root/.config/nvim/plugged/vim-plug/autoload \
    && nvim +UpdateRemotePlugins +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +qall
RUN git clone https://github.com/zplug/zplug $ZPLUG_HOME \
    && zsh $ZPLUG_HOME/init.zsh

WORKDIR /go/src

ENTRYPOINT ["zsh"]
