# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS docker-base

ARG TARGETOS
ARG TARGETARCH

FROM aquasec/trivy:latest AS trivy-uncompressed
RUN apt-get update -qq && apt-get install -y --no-install-recommends upx-ucl \
    && upx --best /usr/local/bin/trivy || true

FROM aquasec/trivy:latest AS trivy
COPY --from=trivy-uncompressed /usr/local/bin/trivy /usr/local/bin/trivy

FROM wagoodman/dive:latest AS dive-base
FROM docker-base AS dive
COPY --link --from=dive-base /usr/local/bin/dive ${BIN_PATH}/dive
RUN (upx --best "${BIN_PATH}/dive" || true)

FROM docker-base AS slim
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=slim REPO='slimtoolkit/$(APP_NAME)' \
        BINS='mint mint-sensor' URL_VER_TAG= EXT=.tar.gz UPX=1 \
        URL_TEMPLATE='$(GITHUB)/slimtoolkit/slim/$(RELEASE_DL)/$(VERSION)/dist_$(OS)$(if $(filter arm64,$(ARCH)),_arm64,).tar.gz' \
    && rm -f "${BIN_PATH}/slim" "${BIN_PATH}/docker-slim" "${BIN_PATH}/docker-slim-sensor" "${BIN_PATH}/slim-sensor" \
    && ln "${BIN_PATH}/mint" "${BIN_PATH}/slim" \
    && ln "${BIN_PATH}/mint" "${BIN_PATH}/docker-slim" \
    && ln "${BIN_PATH}/mint-sensor" "${BIN_PATH}/docker-slim-sensor" \
    && ln "${BIN_PATH}/mint-sensor" "${BIN_PATH}/slim-sensor"

FROM docker-base AS docker-credential-helpers
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=docker-credential-helpers REPO='docker/$(APP_NAME)' \
        BINS='docker-credential-pass docker-credential-secretservice' \
        EXT= UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/{BIN}-v$(VERSION).$(OS)-$(ARCH)'

FROM docker-base AS buildx
ENV CLI_LIB_PATH=/usr/lib/docker/cli-plugins
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    mkdir -p "${CLI_LIB_PATH}" \
    && make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=buildx REPO='docker/$(APP_NAME)' BIN=docker-buildx \
        DEST="${CLI_LIB_PATH}" EXT= UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/$(APP_NAME)-v$(VERSION).$(OS)-$(ARCH)'

FROM docker-base AS dockfmt
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=dockfmt REPO='jessfraz/$(APP_NAME)' \
        VER_IN_NAME=0 EXT= UPX=1

FROM docker-base AS docker-compose
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=docker-compose REPO=docker/compose \
        VER_IN_NAME=0 ARCH_ALIAS='$(XARCH)' EXT= UPX=1

FROM docker-base AS containerd
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=containerd \
        BINS='containerd containerd-shim-runc-v2 containerd-stress ctr' \
        BIN_SUBDIR=bin UPX=1

FROM docker:rc-dind AS common-base

FROM docker-base AS common
COPY --link --from=common-base \
    ${BIN_PATH}/dind \
    ${BIN_PATH}/docker \
    ${BIN_PATH}/docker-entrypoint.sh \
    ${BIN_PATH}/docker-init \
    ${BIN_PATH}/docker-proxy \
    ${BIN_PATH}/dockerd \
    ${BIN_PATH}/dockerd-entrypoint.sh \
    ${BIN_PATH}/modprobe \
    ${BIN_PATH}/runc \
    ${BIN_PATH}/
RUN printf "%s\\n" \
    "${BIN_PATH}/docker" \
    "${BIN_PATH}/docker-init" \
    "${BIN_PATH}/dockerd" \
    "${BIN_PATH}/runc" \
    | xargs -P $(nproc) -n 1 sh -c 'upx --best "$1" 2>/dev/null || upx -t "$1" 2>/dev/null || true' -- \
    && chmod a+x ${BIN_PATH}/docker-entrypoint.sh \
    && chmod a+x ${BIN_PATH}/dockerd-entrypoint.sh

FROM kpango/base:nightly AS docker

ENV DOCKER_PATH=/usr/docker/bin \
    DOCKER_LIB_PATH=/usr/lib/docker

COPY --link --from=buildx ${DOCKER_LIB_PATH}/cli-plugins/docker-buildx ${DOCKER_LIB_PATH}/cli-plugins/docker-buildx
COPY --link --from=common ${BIN_PATH}/dind ${DOCKER_PATH}/dind
COPY --link --from=common ${BIN_PATH}/docker ${DOCKER_PATH}/docker
COPY --link --from=common ${BIN_PATH}/docker-entrypoint.sh ${DOCKER_PATH}/docker-entrypoint
COPY --link --from=common ${BIN_PATH}/docker-init ${DOCKER_PATH}/docker-init
COPY --link --from=common ${BIN_PATH}/docker-proxy ${DOCKER_PATH}/docker-proxy
COPY --link --from=common ${BIN_PATH}/dockerd ${DOCKER_PATH}/dockerd
COPY --link --from=common ${BIN_PATH}/dockerd-entrypoint.sh ${DOCKER_PATH}/dockerd-entrypoint
COPY --link --from=common ${BIN_PATH}/modprobe ${DOCKER_PATH}/modprobe
COPY --link --from=common ${BIN_PATH}/runc ${DOCKER_PATH}/docker-runc
COPY --link --from=containerd ${BIN_PATH}/containerd ${DOCKER_PATH}/containerd
COPY --link --from=containerd ${BIN_PATH}/containerd-shim-runc-v2 ${DOCKER_PATH}/containerd-shim-runc-v2
COPY --link --from=containerd ${BIN_PATH}/containerd-stress ${DOCKER_PATH}/containerd-stress
COPY --link --from=containerd ${BIN_PATH}/ctr ${DOCKER_PATH}/ctr
COPY --link --from=dive ${BIN_PATH}/dive ${DOCKER_PATH}/dive
COPY --link --from=docker-compose ${BIN_PATH}/docker-compose ${DOCKER_LIB_PATH}/cli-plugins/docker-compose
COPY --link --from=docker-credential-helpers ${BIN_PATH}/docker-credential-pass ${DOCKER_PATH}/docker-credential-pass
COPY --link --from=docker-credential-helpers ${BIN_PATH}/docker-credential-secretservice ${DOCKER_PATH}/docker-credential-secretservice
COPY --link --from=dockfmt ${BIN_PATH}/dockfmt ${DOCKER_PATH}/dockfmt
COPY --link --from=slim ${BIN_PATH}/slim ${DOCKER_PATH}/slim
COPY --link --from=slim ${BIN_PATH}/docker-slim ${DOCKER_PATH}/docker-slim
COPY --link --from=slim ${BIN_PATH}/docker-slim-sensor ${DOCKER_PATH}/docker-slim-sensor
COPY --link --from=slim ${BIN_PATH}/slim-sensor ${DOCKER_PATH}/slim-sensor
COPY --link --from=slim ${BIN_PATH}/mint ${DOCKER_PATH}/mint
COPY --link --from=trivy ${BIN_PATH}/trivy ${DOCKER_PATH}/trivy
RUN ln "${DOCKER_PATH}/containerd" "${DOCKER_PATH}/docker-containerd" \
    && ln "${DOCKER_PATH}/containerd-shim-runc-v2" "${DOCKER_PATH}/containerd-shim" \
    && ln "${DOCKER_PATH}/containerd-shim-runc-v2" "${DOCKER_PATH}/docker-containerd-shim" \
    && ln "${DOCKER_PATH}/containerd-shim-runc-v2" "${DOCKER_PATH}/docker-containerd-shim-runc-v2" \
    && ln "${DOCKER_PATH}/containerd-stress" "${DOCKER_PATH}/docker-containerd-stress" \
    && ln "${DOCKER_PATH}/ctr" "${DOCKER_PATH}/docker-containerd-ctr"
