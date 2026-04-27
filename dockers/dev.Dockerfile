FROM kpango/go:nightly AS go

FROM kpango/rust:nightly AS rust

FROM kpango/nim:nightly AS nim

FROM kpango/dart:nightly AS dart

FROM kpango/docker:nightly AS docker

FROM kpango/kube:nightly AS kube

FROM kpango/gcloud:nightly AS gcloud

FROM kpango/env:nightly AS env

FROM env


ARG EMAIL=kpango@vdaas.org
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG WHOAMI=kpango

LABEL maintainer="${WHOAMI} <${EMAIL}>"
ENV GROUP=sudo,root,users,docker,wheel \
    TZ=Asia/Tokyo \
    HOME="/home/${WHOAMI}" \
    USR_LOCAL=/usr/local \
    USR_LIB=/usr/lib

ENV USR_LOCAL_LIB=${USR_LOCAL}/lib \
    BIN_PATH=${USR_LOCAL}/bin \
    GOPATH=${HOME}/go \
    GOROOT=${USR_LOCAL}/go \
    GCLOUD_PATH=${USR_LIB}/google-cloud-sdk \
    DART_PATH=${USR_LIB}/dart \
    HELIX_HOME=${HOME}/.config/helix \
    HELIX_DEFAULT_RUNTIME=${USR_LIB}/helix/runtime

ENV LIBRARY_PATH=/lib:${USR_LIB}:${USR_LOCAL_LIB} \
    RUST_HOME=${USR_LOCAL_LIB}/rust \
    HELIX_RUNTIME=${HELIX_HOME}/runtime

ENV CARGO_HOME=${RUST_HOME}/cargo \
    RUSTUP_HOME=${RUST_HOME}/rustup

ENV PATH=${BIN_PATH}:${GOPATH}/bin:${GOROOT}/bin:${CARGO_HOME}/bin:${DART_PATH}/bin:/opt/nim/bin:${GCLOUD_PATH}/bin:${PATH}

COPY --link --chown=${USER_ID}:${GROUP_ID} --from=docker ${USR_LIB}/docker/cli-plugins/docker-buildx ${USR_LIB}/docker/cli-plugins/docker-compose ${USR_LOCAL_LIB}/docker/cli-plugins/
COPY --link --chown=${USER_ID}:${GROUP_ID} --from=docker /usr/docker/bin/ ${BIN_PATH}/

COPY --link --chown=${USER_ID}:${GROUP_ID} --from=kube /usr/k8s/bin/ ${BIN_PATH}/

COPY --link --chown=${USER_ID}:${GROUP_ID} --from=gcloud ${GCLOUD_PATH}/ ${GCLOUD_PATH}/
COPY --link --chown=${USER_ID}:${GROUP_ID} --from=gcloud /root/.config/gcloud/ ${HOME}/.config/gcloud/

COPY --link --chown=${USER_ID}:${GROUP_ID} --from=nim /opt/nim/ /opt/nim/

COPY --link --chown=${USER_ID}:${GROUP_ID} --from=dart ${DART_PATH}/ ${DART_PATH}/

COPY --link --chown=${USER_ID}:${GROUP_ID} --from=go ${GOROOT}/ ${GOROOT}/
COPY --link --chown=${USER_ID}:${GROUP_ID} --from=go /go/bin/ ${GOPATH}/bin/

COPY --link --chown=${USER_ID}:${GROUP_ID} --from=rust ${RUST_HOME}/ ${RUST_HOME}/
COPY --link --chown=${USER_ID}:${GROUP_ID} --from=rust ${HELIX_DEFAULT_RUNTIME}/ ${HELIX_DEFAULT_RUNTIME}/

USER root

RUN --mount=type=bind,source=gitattributes,target=/tmp/gitattributes,ro \
    --mount=type=bind,source=gitconfig,target=/tmp/gitconfig,ro \
    --mount=type=bind,source=.gitignore,target=/tmp/.gitignore,ro \
    --mount=type=bind,source=tmux-kube,target=/tmp/tmux-kube,ro \
    --mount=type=bind,source=tmux.conf,target=/tmp/tmux.conf,ro \
    --mount=type=bind,source=zshrc,target=/tmp/zshrc,ro \
    --mount=type=bind,source=go.env,target=/tmp/go.env,ro \
    install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/gitattributes "${HOME}/.gitattributes" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/gitconfig "${HOME}/.gitconfig" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/.gitignore "${HOME}/.gitignore" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/tmux-kube "${HOME}/.tmux-kube" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/tmux.conf "${HOME}/.tmux.conf" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/zshrc "${HOME}/.zshrc" \
    && install -m 644 /tmp/go.env "${GOROOT}/go.env" \
    && install -d -m 755 -o "${USER_ID}" -g "${GROUP_ID}" "${HELIX_HOME}" \
    && ln -sf "${HELIX_DEFAULT_RUNTIME}/runtime" "${HELIX_RUNTIME}" \
    && ln -sf /opt/nim/lib "${USR_LOCAL_LIB}/nim" \
    && usermod -aG "${GROUP}" "${WHOAMI}" \
    && chown -R "${USER_ID}:${GROUP_ID}" "${USR_LOCAL}/include/google/protobuf" 2>/dev/null || true \
    && chmod -R 755 "${USR_LOCAL}/include/google/protobuf" 2>/dev/null || true

USER ${USER_ID}
WORKDIR ${HOME}

ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/zsh"]
