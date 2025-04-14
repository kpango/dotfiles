FROM kpango/go:latest AS go

FROM kpango/rust:latest AS rust

FROM kpango/nim:latest AS nim

FROM kpango/dart:latest AS dart

FROM kpango/docker:latest AS docker

FROM kpango/kube:latest AS kube

FROM kpango/gcloud:latest AS gcloud

FROM kpango/env:latest AS env

FROM env


ARG EMAIL=kpango@vdaas.org
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG WHOAMI=kpango

LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV GROUP=sudo,root,users,docker,wheel
ENV TZ=Asia/Tokyo
ENV HOME=/home/${WHOAMI}
ENV USR_LOCAL=/usr/local
ENV USR_LIB=/usr/lib
ENV USR_LOCAL_LIB=${USR_LOCAL}/lib
ENV BIN_PATH=${USR_LOCAL}/bin
ENV LIBRARY_PATH=/lib:${USR_LIB}:${USR_LOCAL_LIB}
ENV GOPATH=${HOME}/go
ENV GOROOT=${USR_LOCAL}/go
ENV GCLOUD_PATH=${USR_LOCAL_LIB}/google-cloud-sdk
ENV RUST_HOME=${USR_LOCAL_LIB}/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV RUSTUP_HOME=${RUST_HOME}/rustup
ENV DART_PATH=${USR_LOCAL_LIB}/dart
ENV NVIM_HOME=$HOME/.config/nvim
ENV PATH=${BIN_PATH}:$GOPATH/bin:${GOROOT}/bin:$CARGO_HOME/bin:$DART_PATH/bin:$PATH
ENV HELIX_DEFAULT_RUNTIME=${USR_LIB}/helix/runtime

COPY --from=docker ${USR_LIB}/docker/cli-plugins/docker-buildx ${USR_LOCAL_LIB}/docker/cli-plugins/docker-buildx
COPY --from=docker ${USR_LIB}/docker/cli-plugins/docker-compose ${USR_LOCAL_LIB}/docker/cli-plugins/docker-compose
COPY --from=docker /usr/docker/bin ${BIN_PATH}
COPY --from=kube /usr/k8s/bin ${BIN_PATH}

COPY --from=gcloud ${GCLOUD_PATH} ${GCLOUD_PATH}
COPY --from=gcloud ${GCLOUD_PATH}/lib ${USR_LOCAL_LIB}
COPY --from=gcloud ${GCLOUD_PATH}/bin ${BIN_PATH}
COPY --from=gcloud /root/.config/gcloud $HOME/.config/gcloud

COPY --from=nim /bin/nim ${BIN_PATH}/nim
COPY --from=nim /bin/nimble ${BIN_PATH}/nimble
COPY --from=nim /bin/nimsuggest ${BIN_PATH}/nimsuggest
COPY --from=nim /nim/lib ${USR_LOCAL_LIB}/nim
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
COPY --from=helix ${HELIX_DEFAULT_RUNTIME} ${HELIX_DEFAULT_RUNTIME}

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
    && chown -R ${USER_ID}:${GROUP_ID} ${USR_LOCAL_LIB}/node_modules \
    && chown -R ${USER_ID}:${GROUP_ID} ${BIN_PATH}/npm \
    && chown -R ${USER_ID}:${GROUP_ID} ${USR_LOCAL}/include/google/protobuf \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && chmod -R 755 ${USR_LOCAL_LIB}/node_modules \
    && chmod -R 755 ${BIN_PATH}/npm \
    && chmod -R 755 ${USR_LOCAL}/include/google/protobuf

USER ${USER_ID}
WORKDIR ${HOME}

ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/zsh"]
