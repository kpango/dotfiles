FROM kpango/go:latest AS go

FROM kpango/rust:latest AS rust

FROM kpango/nim:latest AS nim

FROM kpango/dart:latest AS dart

FROM kpango/docker:latest AS docker

FROM kpango/kube:latest AS kube

FROM kpango/gcloud:latest AS gcloud

FROM kpango/env:latest AS env

FROM env

LABEL maintainer="kpango <kpango@vdaas.org>"

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG WHOAMI=kpango

ENV GROUP sudo,root,users,docker,wheel
ENV TZ Asia/Tokyo
ENV HOME /home/${WHOAMI}
ENV GOPATH $HOME/go
ENV GOROOT /usr/local/go
ENV GCLOUD_PATH /google-cloud-sdk
ENV CARGO_PATH $HOME/.cargo
ENV DART_PATH /usr/lib/dart
ENV NVIM_HOME $HOME/.config/nvim
ENV VIM_PLUG_HOME $NVIM_HOME/plugged/vim-plug
ENV LIBRARY_PATH /usr/local/lib:$LIBRARY_PATH
ENV ZPLUG_HOME $HOME/.zplug
ENV PATH $GOPATH/bin:/usr/local/go/bin:$CARGO_PATH/bin:$DART_PATH/bin:$GCLOUD_PATH/bin:$PATH

COPY --from=docker /usr/lib/docker/cli-plugins/docker-buildx /usr/lib/docker/cli-plugins/docker-buildx
COPY --from=docker /usr/lib/docker/cli-plugins/docker-compose /usr/lib/docker/cli-plugins/docker-compose
COPY --from=docker /usr/docker/bin/ /usr/bin/
COPY --from=kube /usr/k8s/bin/ /usr/bin/

COPY --from=gcloud /usr/lib/google-cloud-sdk /usr/lib/google-cloud-sdk
COPY --from=gcloud /usr/lib/google-cloud-sdk/lib /usr/lib
COPY --from=gcloud /root/.config/gcloud $HOME/.config/gcloud

COPY --from=nim /bin/nim /usr/local/bin/nim
COPY --from=nim /bin/nimble /usr/local/bin/nimble
COPY --from=nim /bin/nimsuggest /usr/local/bin/nimsuggest
COPY --from=nim /nim/lib /usr/local/lib/nim
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

COPY --from=rust /root/.cargo ${CARGO_PATH}
COPY --from=rust /root/.rustup ${HOME}/.rustup

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

# RUN groupadd docker \
    # && newgrp docker \
    # && chown -R ${USER_ID}:${GROUP_ID} ${HOME} \
RUN usermod -aG ${GROUP} ${WHOAMI} \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME} \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME}/.* \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && rm -rf $VIM_PLUG_HOME/autoload \
    && git clone --depth 1 https://github.com/junegunn/vim-plug.git $VIM_PLUG_HOME/autoload \
    && npm uninstall yarn -g \
    && npm install yarn -g \
    && yarn global add https://github.com/neoclide/coc.nvim --prefix /usr/local \
    && git clone --depth 1 https://github.com/zplug/zplug $ZPLUG_HOME \
    && zsh -ic zplug install \
    && rm -rf ${HOME}/.cache \
    && rm -rf ${HOME}/.zplug/cache/* \
    && rm -rf ${HOME}/.zplug/log/* \
    && rm -rf ${HOME}/.npm/_cacache \
    && rm -rf ${HOME}/.cargo/registry/cache \
    && rm -rf /usr/local/share/.cache \
    && rm -rf /tmp/* \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME} \
    && chown -R ${USER_ID}:${GROUP_ID} ${HOME}/.* \
    && chown -R ${USER_ID}:${GROUP_ID} /usr/local/lib/node_modules \
    && chown -R ${USER_ID}:${GROUP_ID} /usr/local/bin/npm \
    && chown -R ${USER_ID}:${GROUP_ID} /usr/local/include/google/protobuf \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && chmod -R 755 /usr/local/lib/node_modules \
    && chmod -R 755 /usr/local/bin/npm \
    && chmod -R 755 /usr/local/include/google/protobuf

USER ${USER_ID}
WORKDIR ${HOME}

ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/zsh"]
