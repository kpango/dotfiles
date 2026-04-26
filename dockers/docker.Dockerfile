# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS docker-base

ARG TARGETOS
ARG TARGETARCH

ENV GITHUB=https://github.com
ENV API_GITHUB=https://api.github.com/repos
ENV GOOGLE=https://storage.googleapis.com
ENV RELEASE_DL=releases/download
ENV RELEASE_LATEST=releases/latest
ENV LOCAL=/usr/local
ENV BIN_PATH=${LOCAL}/bin

FROM aquasec/trivy:latest AS trivy

FROM wagoodman/dive:latest AS dive-base
FROM docker-base AS dive
COPY --link --from=dive-base ${BIN_PATH}/dive ${BIN_PATH}/dive
RUN upx -9 ${BIN_PATH}/dive

FROM docker-base AS slim

RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="slim" \
    && REPO="${BIN_NAME}toolkit/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && DOCKER_SLIM_RELEASES="https://github.com/slimtoolkit/slim/releases/download" \
    && case "${ARCH}" in amd64) SLIM_ARCH="" ;; arm64|aarch64) SLIM_ARCH="_arm64" ;; *) SLIM_ARCH="" ;; esac \
    && curl -fsSLO "${DOCKER_SLIM_RELEASES}/${VERSION}/dist_${OS}${SLIM_ARCH}.tar.gz" \
    && tar zxvf dist_${OS}${SLIM_ARCH}.tar.gz \
    && mv dist_${OS}*/* ${BIN_PATH}/ \
    && BIN_NAME2="mint" \
    && upx -9 \
        ${BIN_PATH}/${BIN_NAME2} \
        ${BIN_PATH}/${BIN_NAME2}-sensor

FROM docker-base AS docker-credential-pass
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker" \
    && NAME="${ORG}-credential-helpers" \
    && REPO="${ORG}/${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && BIN_NAME="${ORG}-credential-pass" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" \
    && mv "${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM docker-base AS docker-credential-secretservice
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker" \
    && NAME="${ORG}-credential-helpers" \
    && REPO="${ORG}/${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && BIN_NAME="${ORG}-credential-secretservice" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" \
    && mv "${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM docker-base AS buildx
ENV CLI_LIB_PATH=/usr/lib/docker/cli-plugins
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && mkdir -p ${CLI_LIB_PATH} \
    && NAME="buildx" \
    && REPO="docker/${NAME}" \
    && BIN_NAME="docker-buildx" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && curl -fsSLo ${CLI_LIB_PATH}/${BIN_NAME} "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-v${VERSION}.${OS}-${ARCH}" \
    && chmod a+x ${CLI_LIB_PATH}/${BIN_NAME} \
    && upx -9 ${CLI_LIB_PATH}/${BIN_NAME}

FROM docker-base AS dockfmt
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && NAME="dockfmt" \
    && REPO="jessfraz/${NAME}" \
    && BIN_NAME=${NAME} \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-${OS}-${ARCH}" \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

# FROM docker-base AS container-diff
# RUN set -x; cd "$(mktemp -d)" \
#     && NAME="container-diff" \
#     && REPO="jessfraz/${NAME}" \
#     && BIN_NAME=${NAME} \
#     && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${NAME}/latest/${NAME}-${OS}-${ARCH}" \
#     && chmod a+x ${BIN_PATH}/${BIN_NAME} \
#     && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM docker-base AS docker-compose
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker"\
    && NAME="compose" \
    && REPO="${ORG}/${NAME}" \
    && BIN_NAME="${ORG}-${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; arm64) ARCH=${AARCH} ;; esac \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ORG}-${NAME}-${OS}-${ARCH}" \
    && mv "${ORG}-${NAME}-${OS}-${ARCH}" ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM docker-base AS containerd
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && NAME="containerd" \
    && REPO="${NAME}/${NAME}" \
    && BIN_NAME=${NAME} \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && TAR_NAME="${NAME}-${VERSION}-${OS}-${ARCH}.tar.gz" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}" \
    && mv "bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && mv "bin/${BIN_NAME}-shim-runc-v2" "${BIN_PATH}/${BIN_NAME}-shim-runc-v2" \
    && mv "bin/${BIN_NAME}-stress" "${BIN_PATH}/${BIN_NAME}-stress" \
    && mv "bin/ctr" "${BIN_PATH}/ctr" \
    && echo "${BIN_PATH}/${BIN_NAME}\n${BIN_PATH}/${BIN_NAME}-shim-runc-v2\n${BIN_PATH}/${BIN_NAME}-stress\n${BIN_PATH}/ctr" | xargs -P $(nproc) -n 1 upx -9

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
RUN printf "%s\\n" "${BIN_PATH}/docker" "${BIN_PATH}/docker-init" "${BIN_PATH}/dockerd" "${BIN_PATH}/runc" | xargs -P $(nproc) -n 1 upx -9 \
    && chmod a+x ${BIN_PATH}/docker-entrypoint.sh \
    && chmod a+x ${BIN_PATH}/dockerd-entrypoint.sh

FROM kpango/base:nightly AS docker

ENV BIN_PATH=/usr/local/bin
ENV LIB_PATH=/usr/local/libexec
ENV DOCKER_PATH=/usr/docker/bin
ENV DOCKER_LIB_PATH=/usr/lib/docker

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
# COPY --from=container-diff ${BIN_PATH}/container-diff ${DOCKER_PATH}/container-diff
COPY --link --from=containerd ${BIN_PATH}/containerd ${DOCKER_PATH}/containerd
COPY --link --from=containerd ${BIN_PATH}/containerd ${DOCKER_PATH}/docker-containerd
COPY --link --from=containerd ${BIN_PATH}/containerd-shim-runc-v2 ${DOCKER_PATH}/containerd-shim
COPY --link --from=containerd ${BIN_PATH}/containerd-shim-runc-v2 ${DOCKER_PATH}/docker-containerd-shim
COPY --link --from=containerd ${BIN_PATH}/containerd-shim-runc-v2 ${DOCKER_PATH}/containerd-shim-runc-v2
COPY --link --from=containerd ${BIN_PATH}/containerd-shim-runc-v2 ${DOCKER_PATH}/docker-containerd-shim-runc-v2
COPY --link --from=containerd ${BIN_PATH}/containerd-stress ${DOCKER_PATH}/containerd-stress
COPY --link --from=containerd ${BIN_PATH}/containerd-stress ${DOCKER_PATH}/docker-containerd-stress
COPY --link --from=containerd ${BIN_PATH}/ctr ${DOCKER_PATH}/ctr
COPY --link --from=containerd ${BIN_PATH}/ctr ${DOCKER_PATH}/docker-containerd-ctr
COPY --link --from=dive ${BIN_PATH}/dive ${DOCKER_PATH}/dive
COPY --link --from=docker-compose ${BIN_PATH}/docker-compose ${DOCKER_LIB_PATH}/cli-plugins/docker-compose
COPY --link --from=docker-credential-pass ${BIN_PATH}/docker-credential-pass ${DOCKER_PATH}/docker-credential-pass
COPY --link --from=docker-credential-secretservice ${BIN_PATH}/docker-credential-secretservice ${DOCKER_PATH}/docker-credential-secretservice
COPY --link --from=dockfmt ${BIN_PATH}/dockfmt ${DOCKER_PATH}/dockfmt
COPY --link --from=slim ${BIN_PATH}/mint ${DOCKER_PATH}/slim
COPY --link --from=slim ${BIN_PATH}/mint ${DOCKER_PATH}/docker-slim
COPY --link --from=slim ${BIN_PATH}/mint-sensor ${DOCKER_PATH}/docker-slim-sensor
COPY --link --from=slim ${BIN_PATH}/mint-sensor ${DOCKER_PATH}/slim-sensor
COPY --link --from=slim ${BIN_PATH}/mint ${DOCKER_PATH}/mint
COPY --link --from=trivy ${BIN_PATH}/trivy ${DOCKER_PATH}/trivy
