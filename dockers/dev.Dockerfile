# syntax = docker/dockerfile:latest
# Source images are provided as named build contexts via --build-context flags
# (dart, docker, gcloud, go, kube, nim, nix, rust, zig).
# This avoids pulling full image manifests as FROM stages, reducing peak disk use.
FROM kpango/tools:nightly

ARG EMAIL=kpango@vdaas.org
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG WHOAMI=kpango

LABEL maintainer="${WHOAMI} <${EMAIL}>"
ENV GROUP=sudo,root,users,docker,wheel \
    TZ=Asia/Tokyo \
    HOME="/home/${WHOAMI}" \
    USR_LOCAL=/usr/local \
    USR_LIB=/usr/lib \
    TERM=xterm-256color \
    COLORTERM=truecolor

ENV USR_LOCAL_LIB=${USR_LOCAL}/lib \
    BIN_PATH=${USR_LOCAL}/bin \
    GOPATH=${HOME}/go \
    GOROOT=${USR_LOCAL}/go \
    GCLOUD_PATH=${USR_LIB}/google-cloud-sdk \
    DART_PATH=${USR_LIB}/dart \
    ZIG_HOME=${USR_LOCAL}/zig \
    HELIX_HOME=${HOME}/.config/helix \
    HELIX_DEFAULT_RUNTIME=${USR_LIB}/helix/runtime \
    NIX_PROFILE=${HOME}/.nix-profile

ENV LIBRARY_PATH=/lib:${USR_LIB}:${USR_LOCAL_LIB} \
    RUST_HOME=${USR_LOCAL_LIB}/rust \
    HELIX_RUNTIME=${HELIX_HOME}/runtime

ENV CARGO_HOME=${RUST_HOME}/cargo \
    RUSTUP_HOME=${RUST_HOME}/rustup \
    NPM_CONFIG_PREFIX=${USR_LOCAL}

ENV PATH=${NIX_PROFILE}/bin:${BIN_PATH}:${GOPATH}/bin:${GOROOT}/bin:${CARGO_HOME}/bin:${DART_PATH}/bin:/opt/nim/bin:${ZIG_HOME}:${GCLOUD_PATH}/bin:${PATH}

COPY --link --from=dart ${DART_PATH}/ ${DART_PATH}/

COPY --link --from=docker ${USR_LIB}/docker/cli-plugins/docker-buildx ${USR_LIB}/docker/cli-plugins/docker-compose ${USR_LOCAL_LIB}/docker/cli-plugins/
COPY --link --from=docker /usr/docker/bin/ ${BIN_PATH}/

COPY --link --from=gcloud ${GCLOUD_PATH}/ ${GCLOUD_PATH}/
COPY --link --chown=${USER_ID}:${GROUP_ID} --from=gcloud /root/.config/gcloud/ ${HOME}/.config/gcloud/

COPY --link --from=go ${GOROOT}/ ${GOROOT}/
COPY --link --chown=${USER_ID}:${GROUP_ID} --from=go /go/bin/ ${GOPATH}/bin/

COPY --link --from=kube /usr/k8s/bin/ ${BIN_PATH}/

COPY --link --from=nim /opt/nim/ /opt/nim/

COPY --link --from=nix /nix /nix
COPY --link --chown=${USER_ID}:${GROUP_ID} --from=nix /root/.nix-profile ${NIX_PROFILE}/

COPY --link --from=rust ${HELIX_DEFAULT_RUNTIME}/ ${HELIX_DEFAULT_RUNTIME}/
COPY --link --from=rust ${RUST_HOME}/ ${RUST_HOME}/

COPY --link --from=zig ${ZIG_HOME}/ ${ZIG_HOME}/
COPY --link --from=zig /usr/local/bin/zls ${BIN_PATH}/zls

USER root

RUN --mount=type=bind,source=gitattributes,target=/tmp/gitattributes,ro \
    --mount=type=bind,source=gitconfig,target=/tmp/gitconfig,ro \
    --mount=type=bind,source=.gitignore,target=/tmp/.gitignore,ro \
    --mount=type=bind,source=tmux.conf,target=/tmp/tmux.conf,ro \
    --mount=type=bind,source=tmux.conf.d,target=/tmp/tmux.conf.d,ro \
    --mount=type=bind,source=zshrc,target=/tmp/zshrc,ro \
    --mount=type=bind,source=go.env,target=/tmp/go.env,ro \
    --mount=type=bind,source=Makefile,target=/tmp/dotfiles/Makefile,ro \
    --mount=type=bind,source=Makefile.d,target=/tmp/dotfiles/Makefile.d,ro \
    --mount=type=bind,source=claude,target=/tmp/dotfiles/claude,ro \
    --mount=type=bind,source=herdr/config.toml,target=/tmp/herdr/config.toml,ro \
    install -d -m 755 -o "${USER_ID}" -g "${GROUP_ID}" \
        "${HOME}/.config/herdr" \
        "${HOME}/.data" \
        "${HOME}/.tmux.conf.d" \
        "${HOME}/.zcache" \
        "${HELIX_HOME}" \
    && make -C /tmp/dotfiles claude/docker/install ROOTDIR=/tmp/dotfiles HOME="${HOME}" USER_ID="${USER_ID}" GROUP_ID="${GROUP_ID}" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/gitattributes "${HOME}/.gitattributes" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/gitconfig "${HOME}/.gitconfig" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/.gitignore "${HOME}/.gitignore" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/herdr/config.toml "${HOME}/.config/herdr/config.toml" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/tmux.conf "${HOME}/.tmux.conf" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/tmux.conf.d/options.conf     "${HOME}/.tmux.conf.d/options.conf" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/tmux.conf.d/keybindings.conf "${HOME}/.tmux.conf.d/keybindings.conf" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/tmux.conf.d/status.conf      "${HOME}/.tmux.conf.d/status.conf" \
    && install -m 755 -o "${USER_ID}" -g "${GROUP_ID}" "${GOPATH}/bin/tmux-pane-info" "${HOME}/.zcache/tmux-pane-info" \
    && install -m 644 -o "${USER_ID}" -g "${GROUP_ID}" /tmp/zshrc "${HOME}/.zshrc" \
    && install -m 644 /tmp/go.env "${GOROOT}/go.env" \
    && ln -sfvn "${HELIX_DEFAULT_RUNTIME}" "${HELIX_RUNTIME}" \
    && ln -sfvn /opt/nim/lib "${USR_LOCAL_LIB}/nim" \
    && ln -sfvn "${BIN_PATH}/bun" "${BIN_PATH}/bunx" \
    && usermod -aG "${GROUP}" "${WHOAMI}" \
    && chown -R "${USER_ID}:${GROUP_ID}" \
        "${DART_PATH}" \
        "${GCLOUD_PATH}" \
        "${GOROOT}" \
        "${RUST_HOME}" \
        "${HELIX_DEFAULT_RUNTIME}" \
        "${ZIG_HOME}" \
        "${BIN_PATH}/zls" \
    && { chown -R "${USER_ID}:${GROUP_ID}" "${USR_LOCAL}/include/google/protobuf" \
         || echo "WARN: ${USR_LOCAL}/include/google/protobuf not found, skipping chown" >&2; } \
    && { chmod -R 755 "${USR_LOCAL}/include/google/protobuf" \
         || echo "WARN: ${USR_LOCAL}/include/google/protobuf not found, skipping chmod" >&2; } \
    && chown -R "${USER_ID}:${GROUP_ID}" "${HOME}"

# Global package install targets (bun/npm/pip) are created as root at build time.
# Make them world-writable with NO sticky bit so the dev user (UID 1000) can
# install, upgrade, and remove global tools without sudo, while root keeps full
# access. Sticky bit is intentionally omitted: it would block cross-user
# upgrade/removal of the root-installed build-time packages. /usr/bin is left
# untouched to preserve setuid-root binaries (e.g. sudo).
RUN set -eux; \
    mkdir -p "${USR_LOCAL}/install/global" "${USR_LOCAL_LIB}/node_modules"; \
    chmod -R a+rwX "${USR_LOCAL}/install/global" "${USR_LOCAL_LIB}/node_modules"; \
    for d in "${USR_LOCAL_LIB}"/python3*/dist-packages; do \
        [ -d "${d}" ] && chmod -R a+rwX "${d}" || true; \
    done; \
    chmod a+rwX "${BIN_PATH}"

USER ${WHOAMI}
WORKDIR ${HOME}

ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/zsh"]
