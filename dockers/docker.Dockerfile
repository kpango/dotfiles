FROM kpango/dev-base:latest AS docker-base

ARG TARGETOS
ARG TARGETARCH
ARG GITHUB_ACCESS_TOKEN

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV XARCH x86_64
ENV GITHUB https://github.com
ENV API_GITHUB https://api.github.com/repos
ENV GOOGLE https://storage.googleapis.com
ENV RELEASE_DL releases/download
ENV RELEASE_LATEST releases/latest
ENV LOCAL /usr/local
ENV BIN_PATH ${LOCAL}/bin

FROM aquasec/trivy:latest AS trivy

FROM goodwithtech/dockle:latest AS dockle-base
FROM docker-base AS dockle
COPY --from=dockle-base /usr/bin/dockle ${BIN_PATH}/dockle
RUN upx -9 ${BIN_PATH}/dockle

FROM wagoodman/dive:latest AS dive-base
FROM docker-base AS dive
COPY --from=dive-base ${BIN_PATH}/dive ${BIN_PATH}/dive
RUN upx -9 ${BIN_PATH}/dive

FROM docker-base AS slim

RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="docker-slim" \
    && REPO="slimtoolkit/slim" \
    && VERSION="$(curl --silent -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && DOCKER_SLIM_RELEASES="https://downloads.dockerslim.com/releases" \
    && curl -fsSLO "${DOCKER_SLIM_RELEASES}/${VERSION}/dist_${OS}.tar.gz" \
    && tar zxvf dist_${OS}.tar.gz \
    && mv dist_${OS}/docker* ${BIN_PATH} \
    && upx -9 \
        ${BIN_PATH}/${BIN_NAME} \
        ${BIN_PATH}/${BIN_NAME}-sensor

FROM docker-base AS docker-credential-pass
RUN set -x; cd "$(mktemp -d)" \
    && ORG="docker" \
    && NAME="${ORG}-credential-helpers" \
    && REPO="${ORG}/${NAME}" \
    && VERSION="$(curl --silent -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && BIN_NAME="${ORG}-credential-pass" \
    && curl -fSsLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" \
    && mv ${BIN_NAME}-v${VERSION}.${OS}-${ARCH} ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM docker-base AS docker-credential-secretservice
RUN set -x; cd "$(mktemp -d)" \
    && ORG="docker" \
    && NAME="${ORG}-credential-helpers" \
    && REPO="${ORG}/${NAME}" \
    && VERSION="$(curl --silent -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && BIN_NAME="${ORG}-credential-secretservice" \
    && curl -fSsLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-v${VERSION}.${OS}-${ARCH}" \
    && mv ${BIN_NAME}-v${VERSION}.${OS}-${ARCH} ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM docker-base AS buildx
ENV CLI_LIB_PATH /usr/lib/docker/cli-plugins
RUN set -x; cd "$(mktemp -d)" \
    && mkdir -p ${CLI_LIB_PATH} \
    && NAME="buildx" \
    && REPO="docker/${NAME}" \
    && BIN_NAME="docker-buildx" \
    && VERSION="$(curl --silent -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && curl -fSsLo ${CLI_LIB_PATH}/${BIN_NAME} "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-v${VERSION}.${OS}-${ARCH}" \
    && chmod a+x ${CLI_LIB_PATH}/${BIN_NAME} \
    && upx -9 ${CLI_LIB_PATH}/${BIN_NAME}

FROM docker-base AS dockfmt
RUN set -x; cd "$(mktemp -d)" \
    && NAME="dockfmt" \
    && REPO="jessfraz/${NAME}" \
    && BIN_NAME=${NAME} \
    && VERSION="$(curl --silent -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && curl -fSsLo ${BIN_PATH}/${BIN_NAME} "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${NAME}-${OS}-${ARCH}" \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM docker-base AS container-diff
RUN set -x; cd "$(mktemp -d)" \
    && NAME="container-diff" \
    && REPO="jessfraz/${NAME}" \
    && BIN_NAME=${NAME} \
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${NAME}/latest/${NAME}-${OS}-${ARCH}" \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM docker-base AS docker-compose
RUN set -x; cd "$(mktemp -d)" \
    && ORG="docker"\
    && NAME="compose" \
    && REPO="${ORG}/${NAME}" \
    && BIN_NAME="${ORG}-${NAME}" \
    && VERSION="$(curl --silent -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && curl -fSsLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ORG}-${NAME}-${OS}-${ARCH}" \
    && mv "${ORG}-${NAME}-${OS}-${ARCH}" ${BIN_PATH}/${BIN_NAME} \
    && chmod a+x ${BIN_PATH}/${BIN_NAME} \
    && upx -9 ${BIN_PATH}/${BIN_NAME}

FROM golang:buster AS dlayer-base
ENV LOCAL /usr/local
ENV BIN_PATH ${LOCAL}/bin
RUN GO111MODULE=on go install  \
    --ldflags "-s -w" --trimpath \
    github.com/orisano/dlayer@latest \
    && mv ${GOPATH}/bin/dlayer ${BIN_PATH}/dlayer

FROM docker-base AS dlayer
COPY --from=dlayer-base ${BIN_PATH}/dlayer ${BIN_PATH}/dlayer
RUN upx -9 ${BIN_PATH}/dlayer

FROM docker-base AS containerd
RUN set -x; cd "$(mktemp -d)" \
    && NAME="containerd" \
    && REPO="${NAME}/${NAME}" \
    && BIN_NAME=${NAME} \
    && VERSION="$(curl --silent -H "Authorization: Bearer ${GITHUB_ACCESS_TOKEN}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
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
        "${BIN_PATH}/${BIN_NAME}-shim-runc-v2" \
        "${BIN_PATH}/${BIN_NAME}-stress" \
        "${BIN_PATH}/ctr"

FROM docker:rc-dind AS common-base

FROM docker-base AS common
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

FROM scratch AS docker

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
COPY --from=container-diff ${BIN_PATH}/container-diff ${DOCKER_PATH}/container-diff
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
COPY --from=dlayer ${BIN_PATH}/dlayer ${DOCKER_PATH}/dlayer
COPY --from=docker-compose ${BIN_PATH}/docker-compose ${DOCKER_LIB_PATH}/cli-plugins/docker-compose
COPY --from=docker-credential-pass ${BIN_PATH}/docker-credential-pass ${DOCKER_PATH}/docker-credential-pass
COPY --from=docker-credential-secretservice ${BIN_PATH}/docker-credential-secretservice ${DOCKER_PATH}/docker-credential-secretservice
COPY --from=dockfmt ${BIN_PATH}/dockfmt ${DOCKER_PATH}/dockfmt
COPY --from=dockle ${BIN_PATH}/dockle ${DOCKER_PATH}/dockle
COPY --from=slim ${BIN_PATH}/docker-slim ${DOCKER_PATH}/docker-slim
COPY --from=slim ${BIN_PATH}/docker-slim-sensor ${DOCKER_PATH}/docker-slim-sensor
COPY --from=trivy ${BIN_PATH}/trivy ${DOCKER_PATH}/trivy
