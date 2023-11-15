# syntax = docker/dockerfile:latest
FROM --platform=$BUILDPLATFORM kpango/base:latest AS docker-base

ARG TARGETOS
ARG TARGETARCH

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV AARCH aarch64
ENV XARCH x86_64
ENV GITHUB https://github.com
ENV API_GITHUB https://api.github.com/repos
ENV GOOGLE https://storage.googleapis.com
ENV RELEASE_DL releases/download
ENV RELEASE_LATEST releases/latest
ENV LOCAL /usr/local
ENV BIN_PATH ${LOCAL}/bin

FROM --platform=$BUILDPLATFORM aquasec/trivy:latest AS trivy

FROM --platform=$BUILDPLATFORM goodwithtech/dockle:latest AS dockle-base
FROM --platform=$BUILDPLATFORM docker-base AS dockle
COPY --from=dockle-base /usr/bin/dockle ${BIN_PATH}/dockle
RUN upx -9 ${BIN_PATH}/dockle

FROM --platform=$BUILDPLATFORM wagoodman/dive:latest AS dive-base
FROM --platform=$BUILDPLATFORM docker-base AS dive
COPY --from=dive-base ${BIN_PATH}/dive ${BIN_PATH}/dive
RUN upx -9 ${BIN_PATH}/dive

FROM --platform=$BUILDPLATFORM docker-base AS slim

RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="slim" \
    && REPO="${BIN_NAME}toolkit/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && DOCKER_SLIM_RELEASES="https://downloads.dockerslim.com/releases" \
    && curl -fsSLO "${DOCKER_SLIM_RELEASES}/${VERSION}/dist_${OS}.tar.gz" \
    && tar zxvf dist_${OS}.tar.gz \
    && mv dist_${OS}/* ${BIN_PATH} \
    && upx -9 \
        ${BIN_PATH}/${BIN_NAME} \
        ${BIN_PATH}/${BIN_NAME}-sensor

FROM --platform=$BUILDPLATFORM docker-base AS docker-credential-pass
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker" \
    && NAME="${ORG}-credential-helpers" \
    && REPO="${ORG}/${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && BIN_NAME="${ORG}-credential-pass" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" \
    && mv ${BIN_NAME}-v${VERSION}.${OS}-${ARCH} ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM docker-base AS docker-credential-secretservice
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker" \
    && NAME="${ORG}-credential-helpers" \
    && REPO="${ORG}/${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && BIN_NAME="${ORG}-credential-secretservice" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" \
    && mv ${BIN_NAME}-v${VERSION}.${OS}-${ARCH} ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM docker-base AS buildx
ENV CLI_LIB_PATH /usr/lib/docker/cli-plugins
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && mkdir -p ${CLI_LIB_PATH} \
    && NAME="buildx" \
    && REPO="docker/${NAME}" \
    && BIN_NAME="docker-buildx" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && curl -fsSLo ${CLI_LIB_PATH}/${BIN_NAME} "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-v${VERSION}.${OS}-${ARCH}" \
    && chmod a+x ${CLI_LIB_PATH}/${BIN_NAME} \
    && upx -9 ${CLI_LIB_PATH}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM docker-base AS dockfmt
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && NAME="dockfmt" \
    && REPO="jessfraz/${NAME}" \
    && BIN_NAME=${NAME} \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && curl -fsSLo ${BIN_PATH}/${BIN_NAME} "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-${OS}-${ARCH}" \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

# FROM --platform=$BUILDPLATFORM docker-base AS container-diff
# RUN set -x; cd "$(mktemp -d)" \
#     && NAME="container-diff" \
#     && REPO="jessfraz/${NAME}" \
#     && BIN_NAME=${NAME} \
#     && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${NAME}/latest/${NAME}-${OS}-${ARCH}" \
#     && chmod a+x ${BIN_PATH}/${BIN_NAME} \
#     && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM docker-base AS docker-compose
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker"\
    && NAME="compose" \
    && REPO="${ORG}/${NAME}" \
    && BIN_NAME="${ORG}-${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && if [ "${ARCH}" = "arm64" ] ; then  ARCH=${AARCH} ; fi \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ORG}-${NAME}-${OS}-${ARCH}" \
    && mv "${ORG}-${NAME}-${OS}-${ARCH}" ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM --platform=$BUILDPLATFORM docker-base AS containerd
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && NAME="containerd" \
    && REPO="${NAME}/${NAME}" \
    && BIN_NAME=${NAME} \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && TAR_NAME="${NAME}-${VERSION}-${OS}-${ARCH}.tar.gz" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}" \
    && mv "bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && mv "bin/${BIN_NAME}-shim" "${BIN_PATH}/${BIN_NAME}-shim" \
    && mv "bin/${BIN_NAME}-shim-runc-v1" "${BIN_PATH}/${BIN_NAME}-shim-runc-v1" \
    && mv "bin/${BIN_NAME}-shim-runc-v2" "${BIN_PATH}/${BIN_NAME}-shim-runc-v2" \
    && mv "bin/${BIN_NAME}-stress" "${BIN_PATH}/${BIN_NAME}-stress" \
    && mv "bin/ctr" "${BIN_PATH}/ctr" \
    && upx -9 \
        "${BIN_PATH}/${BIN_NAME}" \
        "${BIN_PATH}/${BIN_NAME}-shim" \
        "${BIN_PATH}/${BIN_NAME}-shim-runc-v1" \
        "${BIN_PATH}/${BIN_NAME}-shim-runc-v2"

FROM --platform=$BUILDPLATFORM docker:rc-dind AS common-base

FROM --platform=$BUILDPLATFORM docker-base AS common
COPY --from=common-base ${BIN_PATH}/dind ${BIN_PATH}/dind
COPY --from=common-base ${BIN_PATH}/docker ${BIN_PATH}/docker
COPY --from=common-base ${BIN_PATH}/docker-entrypoint.sh ${BIN_PATH}/docker-entrypoint.sh
COPY --from=common-base ${BIN_PATH}/docker-init ${BIN_PATH}/docker-init
COPY --from=common-base ${BIN_PATH}/docker-proxy ${BIN_PATH}/docker-proxy
COPY --from=common-base ${BIN_PATH}/dockerd ${BIN_PATH}/dockerd
COPY --from=common-base ${BIN_PATH}/dockerd-entrypoint.sh ${BIN_PATH}/dockerd-entrypoint.sh
COPY --from=common-base ${BIN_PATH}/modprobe ${BIN_PATH}/modprobe
COPY --from=common-base ${BIN_PATH}/runc ${BIN_PATH}/runc
RUN upx -9 \
        ${BIN_PATH}/docker \
        ${BIN_PATH}/docker-init \
        ${BIN_PATH}/dockerd \
        ${BIN_PATH}/runc \
    # && upx -9 --force-pie \
        # ${BIN_PATH}/ctr \
    && chmod a+x ${BIN_PATH}/docker-entrypoint.sh \
    && chmod a+x ${BIN_PATH}/dockerd-entrypoint.sh

FROM --platform=$BUILDPLATFORM kpango/base:latest AS docker

ENV BIN_PATH /usr/local/bin
ENV LIB_PATH /usr/local/libexec
ENV DOCKER_PATH /usr/docker/bin
ENV DOCKER_LIB_PATH /usr/lib/docker

COPY --from=buildx ${DOCKER_LIB_PATH}/cli-plugins/docker-buildx ${DOCKER_LIB_PATH}/cli-plugins/docker-buildx
COPY --from=common ${BIN_PATH}/dind ${DOCKER_PATH}/dind
COPY --from=common ${BIN_PATH}/docker ${DOCKER_PATH}/docker
COPY --from=common ${BIN_PATH}/docker-entrypoint.sh ${DOCKER_PATH}/docker-entrypoint
COPY --from=common ${BIN_PATH}/docker-init ${DOCKER_PATH}/docker-init
COPY --from=common ${BIN_PATH}/docker-proxy ${DOCKER_PATH}/docker-proxy
COPY --from=common ${BIN_PATH}/dockerd ${DOCKER_PATH}/dockerd
COPY --from=common ${BIN_PATH}/dockerd-entrypoint.sh ${DOCKER_PATH}/dockerd-entrypoint
COPY --from=common ${BIN_PATH}/modprobe ${DOCKER_PATH}/modprobe
COPY --from=common ${BIN_PATH}/runc ${DOCKER_PATH}/docker-runc
# COPY --from=container-diff ${BIN_PATH}/container-diff ${DOCKER_PATH}/container-diff
COPY --from=containerd ${BIN_PATH}/containerd ${DOCKER_PATH}/containerd
COPY --from=containerd ${BIN_PATH}/containerd ${DOCKER_PATH}/docker-containerd
COPY --from=containerd ${BIN_PATH}/containerd-shim ${DOCKER_PATH}/containerd-shim
COPY --from=containerd ${BIN_PATH}/containerd-shim ${DOCKER_PATH}/docker-containerd-shim
COPY --from=containerd ${BIN_PATH}/containerd-shim-runc-v1 ${DOCKER_PATH}/containerd-shim-runc-v1
COPY --from=containerd ${BIN_PATH}/containerd-shim-runc-v1 ${DOCKER_PATH}/docker-containerd-shim-runc-v1
COPY --from=containerd ${BIN_PATH}/containerd-shim-runc-v2 ${DOCKER_PATH}/containerd-shim-runc-v2
COPY --from=containerd ${BIN_PATH}/containerd-shim-runc-v2 ${DOCKER_PATH}/docker-containerd-shim-runc-v2
COPY --from=containerd ${BIN_PATH}/containerd-stress ${DOCKER_PATH}/containerd-stress
COPY --from=containerd ${BIN_PATH}/containerd-stress ${DOCKER_PATH}/docker-containerd-stress
COPY --from=containerd ${BIN_PATH}/ctr ${DOCKER_PATH}/ctr
COPY --from=containerd ${BIN_PATH}/ctr ${DOCKER_PATH}/docker-containerd-ctr
COPY --from=dive ${BIN_PATH}/dive ${DOCKER_PATH}/dive
COPY --from=docker-compose ${BIN_PATH}/docker-compose ${DOCKER_LIB_PATH}/cli-plugins/docker-compose
COPY --from=docker-credential-pass ${BIN_PATH}/docker-credential-pass ${DOCKER_PATH}/docker-credential-pass
COPY --from=docker-credential-secretservice ${BIN_PATH}/docker-credential-secretservice ${DOCKER_PATH}/docker-credential-secretservice
COPY --from=dockfmt ${BIN_PATH}/dockfmt ${DOCKER_PATH}/dockfmt
COPY --from=dockle ${BIN_PATH}/dockle ${DOCKER_PATH}/dockle
COPY --from=slim ${BIN_PATH}/slim ${DOCKER_PATH}/docker-slim
COPY --from=slim ${BIN_PATH}/slim-sensor ${DOCKER_PATH}/docker-slim-sensor
COPY --from=slim ${BIN_PATH}/slim ${DOCKER_PATH}/slim
COPY --from=slim ${BIN_PATH}/slim-sensor ${DOCKER_PATH}/slim-sensor
COPY --from=trivy ${BIN_PATH}/trivy ${DOCKER_PATH}/trivy
