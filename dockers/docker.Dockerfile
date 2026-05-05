# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS docker-base

ARG TARGETOS
ARG TARGETARCH

FROM aquasec/trivy:latest AS trivy

FROM wagoodman/dive:latest AS dive-base
FROM docker-base AS dive
COPY --link --from=dive-base /usr/local/bin/dive ${BIN_PATH}/dive
RUN (upx --best "${BIN_PATH}/dive" || true)

FROM docker-base AS slim

RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="slim" \
    && REPO="${BIN_NAME}toolkit/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && DOCKER_SLIM_RELEASES="${GITHUB}/slimtoolkit/slim/${RELEASE_DL}" \
    && case "${ARCH}" in amd64) SLIM_ARCH="" ;; arm64|aarch64) SLIM_ARCH="_arm64" ;; *) SLIM_ARCH="" ;; esac \
    && URL="${DOCKER_SLIM_RELEASES}/${VERSION}/dist_${OS}${SLIM_ARCH}.tar.gz" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL}" \
    && tar zxvf dist_${OS}${SLIM_ARCH}.tar.gz \
    && mv dist_${OS}*/* ${BIN_PATH}/ \
    && BIN_NAME2="mint" \
    && upx --best \
        ${BIN_PATH}/${BIN_NAME2} \
        ${BIN_PATH}/${BIN_NAME2}-sensor \
    && rm -f "${BIN_PATH}/slim" "${BIN_PATH}/docker-slim" "${BIN_PATH}/docker-slim-sensor" "${BIN_PATH}/slim-sensor" \
    && cp "${BIN_PATH}/${BIN_NAME2}" "${BIN_PATH}/slim" \
    && cp "${BIN_PATH}/${BIN_NAME2}" "${BIN_PATH}/docker-slim" \
    && cp "${BIN_PATH}/${BIN_NAME2}-sensor" "${BIN_PATH}/docker-slim-sensor" \
    && cp "${BIN_PATH}/${BIN_NAME2}-sensor" "${BIN_PATH}/slim-sensor"

FROM docker-base AS docker-credential-helpers
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker" \
    && NAME="${ORG}-credential-helpers" \
    && REPO="${ORG}/${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && BIN_PASS="${ORG}-credential-pass" \
    && URL_PASS="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_PASS}-v${VERSION}.${OS}-${ARCH}" \
    && echo ${URL_PASS} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL_PASS}" \
    && mv "${BIN_PASS}-v${VERSION}.${OS}-${ARCH}" "${BIN_PATH}/${BIN_PASS}" \
    && chmod a+x "${BIN_PATH}/${BIN_PASS}" \
    && (upx --best "${BIN_PATH}/${BIN_PASS}" || true) \
    && BIN_SS="${ORG}-credential-secretservice" \
    && URL_SS="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_SS}-v${VERSION}.${OS}-${ARCH}" \
    && echo ${URL_SS} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL_SS}" \
    && mv "${BIN_SS}-v${VERSION}.${OS}-${ARCH}" "${BIN_PATH}/${BIN_SS}" \
    && chmod a+x "${BIN_PATH}/${BIN_SS}" \
    && (upx --best "${BIN_PATH}/${BIN_SS}" || true)

FROM docker-base AS buildx
ENV CLI_LIB_PATH=/usr/lib/docker/cli-plugins
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && mkdir -p ${CLI_LIB_PATH} \
    && NAME="buildx" \
    && REPO="docker/${NAME}" \
    && BIN_NAME="docker-buildx" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-v${VERSION}.${OS}-${ARCH}" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo ${CLI_LIB_PATH}/${BIN_NAME} "${URL}" \
    && chmod a+x ${CLI_LIB_PATH}/${BIN_NAME} \
    && (upx --best "${CLI_LIB_PATH}/${BIN_NAME}" || true)

FROM docker-base AS dockfmt
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && NAME="dockfmt" \
    && REPO="jessfraz/${NAME}" \
    && BIN_NAME=${NAME} \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-${OS}-${ARCH}" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${BIN_PATH}/${BIN_NAME}" "${URL}" \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)

FROM docker-base AS docker-compose
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && ORG="docker"\
    && NAME="compose" \
    && REPO="${ORG}/${NAME}" \
    && BIN_NAME="${ORG}-${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; arm64) ARCH=${AARCH} ;; esac \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ORG}-${NAME}-${OS}-${ARCH}" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL}" \
    && mv "${ORG}-${NAME}-${OS}-${ARCH}" ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)

FROM docker-base AS containerd
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && NAME="containerd" \
    && REPO="${NAME}/${NAME}" \
    && BIN_NAME=${NAME} \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST} \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="${NAME}-${VERSION}-${OS}-${ARCH}.tar.gz" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}" \
    && mv "bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && mv "bin/${BIN_NAME}-shim-runc-v2" "${BIN_PATH}/${BIN_NAME}-shim-runc-v2" \
    && mv "bin/${BIN_NAME}-stress" "${BIN_PATH}/${BIN_NAME}-stress" \
    && mv "bin/ctr" "${BIN_PATH}/ctr" \
    && printf "%s\\n" \
        "${BIN_PATH}/${BIN_NAME}" \
        "${BIN_PATH}/${BIN_NAME}-shim-runc-v2" \
        "${BIN_PATH}/${BIN_NAME}-stress" \
        "${BIN_PATH}/ctr" \
        | xargs -P $(nproc) -n 1 sh -c 'upx --best "$1" 2>/dev/null || upx -t "$1" 2>/dev/null || true' --

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
COPY --link --from=docker-credential-helpers ${BIN_PATH}/docker-credential-pass ${DOCKER_PATH}/docker-credential-pass
COPY --link --from=docker-credential-helpers ${BIN_PATH}/docker-credential-secretservice ${DOCKER_PATH}/docker-credential-secretservice
COPY --link --from=dockfmt ${BIN_PATH}/dockfmt ${DOCKER_PATH}/dockfmt
COPY --link --from=slim ${BIN_PATH}/slim ${DOCKER_PATH}/slim
COPY --link --from=slim ${BIN_PATH}/docker-slim ${DOCKER_PATH}/docker-slim
COPY --link --from=slim ${BIN_PATH}/docker-slim-sensor ${DOCKER_PATH}/docker-slim-sensor
COPY --link --from=slim ${BIN_PATH}/slim-sensor ${DOCKER_PATH}/slim-sensor
COPY --link --from=slim ${BIN_PATH}/mint ${DOCKER_PATH}/mint
COPY --link --from=trivy ${BIN_PATH}/trivy ${DOCKER_PATH}/trivy
