FROM kpango/go:latest AS go

FROM kpango/rust:latest AS rust

FROM kpango/nim:latest AS nim

FROM kpango/dart:latest AS dart

FROM kpango/docker:latest AS docker

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

FROM kpango/kube:latest AS kube

FROM kpango/gcloud:latest AS gcloud

FROM kpango/glibc:latest AS glibc

FROM kpango/env:latest AS env

FROM env

LABEL maintainer="kpango <i.can.feel.gravity@gmail.com>"

ENV TZ Asia/Tokyo
ENV HOME /root
ENV GOPATH /go
ENV GOROOT /usr/local/go
ENV GCLOUD_PATH /google-cloud-sdk
ENV CARGO_PATH /root/.cargo
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

# etc lib sbin bin
# COPY --from=glibc /usr/glibc-compat /usr/glibc-compat

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
COPY --from=kube /usr/local/bin/kubebox /usr/bin/kubebox
COPY --from=kube /usr/local/bin/kubebuilder /usr/bin/kubebuilder
COPY --from=kube /usr/local/bin/stern /usr/bin/stern
COPY --from=kube /usr/local/bin/helm /usr/bin/helm
COPY --from=kube /root/.krew/bin /usr/bin/

COPY --from=gcloud /google-cloud-sdk /google-cloud-sdk
COPY --from=gcloud /root/.config/gcloud /root/.config/gcloud

# COPY --from=nim /bin/nim /usr/local/bin/nim
# COPY --from=nim /bin/nimble /usr/local/bin/nimble
# COPY --from=nim /bin/nimsuggest /usr/local/bin/nimsuggest
# COPY --from=nim /nim/lib /usr/local/lib/nim
# COPY --from=nim /root/.cache/nim /root/.cache/nim
# COPY --from=nim /nim /nim

COPY --from=dart /usr/lib/dart/bin /usr/lib/dart/bin
# COPY --from=dart /usr/lib/dart/lib /usr/lib/dart/lib
# COPY --from=dart /usr/lib/dart/include /usr/lib/dart/include

COPY --from=go /usr/local/go/bin $GOROOT/bin
COPY --from=go /usr/local/go/src $GOROOT/src
COPY --from=go /usr/local/go/lib $GOROOT/lib
COPY --from=go /usr/local/go/pkg $GOROOT/pkg
COPY --from=go /usr/local/go/misc $GOROOT/misc
COPY --from=go /go/bin $GOPATH/bin
# COPY --from=go /go/src/github.com/nsf/gocode/vim $GOROOT/misc/vim

COPY --from=rust /root/.cargo/bin /root/.cargo/bin
# COPY --from=rust /root/.cargo /root/.cargo
# COPY --from=rust /root/.rustup /root/.rustup
# COPY --from=rust /root/.multirust /root/.multirust

COPY coc-settings.json $NVIM_HOME/coc-settings.json
COPY efm-lsp-conf.yaml $NVIM_HOME/efm-lsp-conf.yaml
COPY gitattributes $HOME/.gitattributes
COPY gitconfig $HOME/.gitconfig
COPY gitignore $HOME/.gitignore
COPY init.vim $NVIM_HOME/init.vim
COPY monokai.vim $NVIM_HOME/colors/monokai.vim
COPY tmux-kube $HOME/.tmux-kube
COPY tmux.conf $HOME/.tmux.conf
COPY vintrc.yaml $HOME/.vintrc.yaml
COPY zshrc $HOME/.zshrc

ENV SHELL /bin/zsh

RUN  ["/bin/zsh", "-c", "source ~/.zshrc"]

WORKDIR $NVIM_HOME/plugged/vim-plug

RUN rm -rf /root/.config/nvim/plugged/vim-plug/autoload \
    && git clone https://github.com/junegunn/vim-plug.git /root/.config/nvim/plugged/vim-plug/autoload \
    && nvim +PlugInstall +PlugUpdate +PlugUpgrade +PlugClean +UpdateRemotePlugins +GoInstallBinaries +qall main.go \
    && yarn global add https://github.com/neoclide/coc.nvim --prefix /usr/local \
    && nvim +CocInstall coc-rls coc-json coc-yaml coc-snippets coc-java coc-dictionary coc-tag coc-word coc-omni +qall \
    && git clone https://github.com/zplug/zplug $ZPLUG_HOME \
    && rm -rf $HOME/.cache \
    && rm -rf $HOME/.npm/_cacache \
    && rm -rf $HOME/.cargo/registry/cache \
    && rm -rf /usr/local/share/.cache \
    && rm -rf /tmp/*


WORKDIR /go/src

ENTRYPOINT ["docker-entrypoint"]
CMD ["zsh"]
