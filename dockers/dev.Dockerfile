FROM --platform=$BUILDPLATFORM kpango/go:latest AS go

FROM --platform=$BUILDPLATFORM kpango/rust:latest AS rust

FROM --platform=$BUILDPLATFORM kpango/nim:latest AS nim

FROM --platform=$BUILDPLATFORM kpango/dart:latest AS dart

FROM --platform=$BUILDPLATFORM kpango/docker:latest AS docker

FROM --platform=$BUILDPLATFORM kpango/kube:latest AS kube

FROM --platform=$BUILDPLATFORM kpango/gcloud:latest AS gcloud

FROM --platform=$BUILDPLATFORM kpango/env:latest AS env

FROM --platform=$BUILDPLATFORM env


ARG EMAIL=kpango@vdaas.org
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG WHOAMI=kpango

LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV GROUP=sudo,root,users,docker,wheel
ENV TZ=Asia/Tokyo
ENV HOME=/home/${WHOAMI}
ENV USR_LOCAL=/usr/local
ENV BIN_PATH=${USR_LOCAL}/bin
ENV LIBRARY_PATH=${USR_LOCAL}/lib
ENV GOPATH=${HOME}/go
ENV GOROOT=${USR_LOCAL}/go
ENV GCLOUD_PATH=${LIBRARY_PATH}/google-cloud-sdk
ENV RUST_HOME=${LIBRARY_PATH}/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV RUSTUP_HOME=${RUST_HOME}/rustup
ENV DART_PATH=${LIBRARY_PATH}}/dart
ENV NVIM_HOME=$HOME/.config/nvim
ENV PATH=${BIN_PATH}:$GOPATH/bin:${GOROOT}/bin:$CARGO_HOME/bin:$DART_PATH/bin:$PATH
ENV LD_LIBRARY_PATH=/lib:/usr/lib:${LIBRARY_PATH}

COPY --from=docker /usr/lib/docker/cli-plugins/docker-buildx ${LIBRARY_PATH}/docker/cli-plugins/docker-buildx
COPY --from=docker /usr/lib/docker/cli-plugins/docker-compose ${LIBRARY_PATH}/docker/cli-plugins/docker-compose
COPY --from=docker /usr/docker/bin ${BIN_PATH}
COPY --from=kube /usr/k8s/bin ${BIN_PATH}

COPY --from=gcloud ${GCLOUD_PATH} ${GCLOUD_PATH}
COPY --from=gcloud ${GCLOUD_PATH}/lib ${LIBRARY_PATH}
COPY --from=gcloud ${GCLOUD_PATH}/bin ${BIN_PATH}
COPY --from=gcloud /root/.config/gcloud $HOME/.config/gcloud

COPY --from=nim /bin/nim ${BIN_PATH}/nim
COPY --from=nim /bin/nimble ${BIN_PATH}/nimble
COPY --from=nim /bin/nimsuggest ${BIN_PATH}/nimsuggest
COPY --from=nim /nim/lib ${LIBRARY_PATH}/nim
COPY --from=nim /root/.cache/nim $HOME/.cache/nim
COPY --from=nim /nim /nim

COPY --from=dart ${DART_PATH}/bin ${DART_PATH}/bin
COPY --from=dart ${DART_PATH}/lib ${DART_PATH}/lib
COPY --from=dart ${DART_PATH}/include ${DART_PATH}/include

COPY --from=go /opt/go/bin $GOROOT/bin
COPY --from=go /opt/go/src $GOROOT/src
COPY --from=go /opt/go/lib $GOROOT/lib
COPY --from=go /opt/go/pkg $GOROOT/pkg
COPY --from=go /opt/go/misc $GOROOT/misc
COPY --from=go /go/bin $GOPATH/bin

COPY --from=rust ${RUST_HOME} ${RUST_HOME}

COPY gitattributes $HOME/.gitattributes
COPY gitconfig $HOME/.gitconfig
COPY gitignore $HOME/.gitignore
COPY nvim/init.lua $NVIM_HOME/init.lua
COPY nvim/lua $NVIM_HOME/lua
COPY nvim/luacheckrc $NVIM_HOME/luacheckrc
COPY tmux-kube $HOME/.tmux-kube
COPY tmux.conf $HOME/.tmux.conf
COPY zshrc $HOME/.zshrc
COPY go.env $GOROOT/go.env

USER root

RUN usermod -aG ${GROUP} ${WHOAMI} \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME} \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME}/.* \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && rm -rf $VIM_PLUG_HOME/autoload \
    && rm -rf ${HOME}/.cache \
    && rm -rf ${HOME}/.npm/_cacache \
    && rm -rf ${CARGO_HOME}/registry/cache \
    && rm -rf ${USR_LOCAL}/share/.cache \
    && rm -rf /tmp/* \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME} \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME}/.* \
    && chown -R ${USER_ID}:${GROUP_ID} ${LIBRARY_PATH}/node_modules \
    && chown -R ${USER_ID}:${GROUP_ID} ${BIN_PATH}/npm \
    && chown -R ${USER_ID}:${GROUP_ID} ${USR_LOCAL}/include/google/protobuf \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && chmod -R 755 ${LIBRARY_PATH}/node_modules \
    && chmod -R 755 ${BIN_PATH}/npm \
    && chmod -R 755 ${USR_LOCAL}}/include/google/protobuf

USER ${USER_ID}
WORKDIR ${HOME}

ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/zsh"]
