FROM kpango/go:latest AS go


FROM kpango/rust:latest AS rust

FROM kpango/nim:latest AS nim

FROM kpango/dart:latest AS dart

FROM kpango/docker:latest AS docker

# FROM node:13-alpine AS node

# RUN npm config set user  root \
#     && npm install -g neovim resume-cli

# FROM python:3.8-alpine AS python3

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

FROM kpango/env:latest AS env

FROM env

LABEL maintainer="kpango <kpango@vdaas.org>"

ENV TZ Asia/Tokyo
ENV GOPATH $HOME/go
ENV GOROOT /usr/local/go
ENV GCLOUD_PATH /google-cloud-sdk
ENV CARGO_PATH $HOME/.cargo
ENV DART_PATH /usr/lib/dart
ENV PATH $GOPATH/bin:/usr/local/go/bin:$CARGO_PATH/bin:$DART_PATH/bin:$GCLOUD_PATH/bin:$PATH
ENV NVIM_HOME $HOME/.config/nvim
ENV VIM_PLUG_HOME $NVIM_HOME/plugged/vim-plug
ENV LIBRARY_PATH /usr/local/lib:$LIBRARY_PATH
ENV ZPLUG_HOME $HOME/.zplug

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

COPY --from=docker /usr/bin/dind /usr/bin/dind
COPY --from=docker /usr/bin/dive /usr/bin/dive
COPY --from=docker /usr/bin/dlayer /usr/bin/dlayer
COPY --from=docker /usr/bin/docker /usr/bin/docker
COPY --from=docker /usr/bin/docker-containerd /usr/bin/docker-containerd
COPY --from=docker /usr/bin/docker-containerd-ctr /usr/bin/docker-containerd-ctr
COPY --from=docker /usr/bin/docker-containerd-shim /usr/bin/docker-containerd-shim
COPY --from=docker /usr/bin/docker-entrypoint /usr/bin/docker-entrypoint
COPY --from=docker /usr/bin/docker-init /usr/bin/docker-init
COPY --from=docker /usr/bin/docker-proxy /usr/bin/docker-proxy
COPY --from=docker /usr/bin/docker-runc /usr/bin/docker-runc
COPY --from=docker /usr/bin/docker-slim /usr/bin/docker-slim
COPY --from=docker /usr/bin/docker-slim-sensor /usr/bin/docker-slim-sensor
COPY --from=docker /usr/bin/dockerd /usr/bin/dockerd
COPY --from=docker /usr/bin/dockerd-entrypoint /usr/bin/dockerd-entrypoint
COPY --from=docker /usr/bin/dockfmt /usr/bin/dockfmt
COPY --from=docker /usr/bin/dockle /usr/bin/dockle
COPY --from=docker /usr/bin/container-diff /usr/bin/container-diff
COPY --from=docker /usr/bin/modprobe /usr/bin/modprobe
COPY --from=docker /usr/bin/trivy /usr/bin/trivy
COPY --from=docker /usr/lib/docker/cli-plugins/docker-buildx /usr/lib/docker/cli-plugins/docker-buildx
COPY --from=kube /usr/k8s/bin/ /usr/bin/
COPY --from=kube /usr/k8s/lib/ /usr/lib/

COPY --from=gcloud /usr/lib/google-cloud-sdk /usr/lib/google-cloud-sdk
COPY --from=gcloud /usr/lib/google-cloud-sdk/lib /usr/lib
COPY --from=gcloud /root/.config/gcloud $HOME/.config/gcloud

COPY --from=nim /bin/nim /usr/local/bin/nim
COPY --from=nim /bin/nimble /usr/local/bin/nimble
COPY --from=nim /bin/nimsuggest /usr/local/bin/nimsuggest
COPY --from=nim /nim/lib /usr/local/lib/nim
COPY --from=nim /root/.cache/nim $HOME/.cache/nim
COPY --from=nim /nim /nim

COPY --from=dart /usr/lib/dart/bin /usr/lib/dart/bin
COPY --from=dart /usr/lib/dart/lib /usr/lib/dart/lib
COPY --from=dart /usr/lib/dart/include /usr/lib/dart/include

COPY --from=go /opt/go/bin $GOROOT/bin
COPY --from=go /opt/go/src $GOROOT/src
COPY --from=go /opt/go/lib $GOROOT/lib
COPY --from=go /opt/go/pkg $GOROOT/pkg
COPY --from=go /opt/go/misc $GOROOT/misc
COPY --from=go /go/bin $GOPATH/bin

COPY --from=rust /root/.cargo $HOME/.cargo
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

WORKDIR $VIM_PLUG_HOME

USER root
RUN chown -R kpango:users ${HOME} \
    && chown -R kpango:users ${HOME}/.* \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && rm -rf $VIM_PLUG_HOME/autoload \
    && git clone https://github.com/junegunn/vim-plug.git $VIM_PLUG_HOME/autoload \
    && npm uninstall yarn -g \
    && npm install yarn -g \
    && yarn global add https://github.com/neoclide/coc.nvim --prefix /usr/local \
    && git clone https://github.com/zplug/zplug $ZPLUG_HOME \
    && rm -rf $HOME/.cache \
    && rm -rf $HOME/.npm/_cacache \
    && rm -rf $HOME/.cargo/registry/cache \
    && rm -rf /usr/local/share/.cache \
    && rm -rf /tmp/* \
    && chown -R kpango:users ${HOME} \
    && chown -R kpango:users ${HOME}/.* \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.*

USER ${USER}
WORKDIR ${HOME}

ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/zsh"]
