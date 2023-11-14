# syntax = docker/dockerfile:latest
FROM --platform=$BUILDPLATFORM kpango/base:latest AS kube-base

ARG TARGETOS
ARG TARGETARCH
ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV AARCH aarch64
ENV XARCH x86_64
ENV GITHUBCOM github.com
ENV GITHUB https://${GITHUBCOM}
ENV API_GITHUB https://api.github.com/repos
ENV RAWGITHUB https://raw.githubusercontent.com
ENV GOOGLE https://storage.googleapis.com
ENV RELEASE_DL releases/download
ENV RELEASE_LATEST releases/latest
ENV LOCAL /usr/local
ENV BIN_PATH ${LOCAL}/bin

RUN mkdir -p "${BIN_PATH}"

FROM --platform=$BUILDPLATFORM kube-base AS kubectl
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kubectl" \
    && VERSION="$(curl -s ${GOOGLE}/kubernetes-release/release/stable.txt)" \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${VERSION}" >&2; exit 1; } \
    && URL="${GOOGLE}/kubernetes-release/release/${VERSION}/bin/${OS}/${ARCH}/${BIN_NAME}" \
    && echo ${URL} \
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${URL}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}" \
    && "${BIN_PATH}/${BIN_NAME}" version --client

FROM --platform=$BUILDPLATFORM kube-base AS helm
RUN set -x; cd "$(mktemp -d)" \
    && curl "${RAWGITHUB}/helm/helm/main/scripts/get-helm-3" | bash \
    && BIN_NAME="helm" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubefwd
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubefwd" \
    && REPO="txn2/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && TAR_NAME="${BIN_NAME}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubectx
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectx" \
    && REPO="ahmetb/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && TAR_NAME="${BIN_NAME}_v${VERSION}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubens
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectx" \
    && REPO="ahmetb/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && BIN_NAME="kubens" \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && TAR_NAME="${BIN_NAME}_v${VERSION}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS krew
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="krew" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}-${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}.yaml" \
    && "${PWD}/${TAR_NAME}" install --manifest="${BIN_NAME}.yaml" --archive="${TAR_NAME}.tar.gz" \
    && BIN_NAME="kubectl-krew" \
    && "/root/.krew/bin/${BIN_NAME}" update \
    && mv "/root/.krew/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS check-ownerreferences
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-check-ownerreferences" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}-${OS}-${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubebox
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubebox" \
    && REPO="astefanutti/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-${OS}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS stern
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="stern" \
    && REPO="${BIN_NAME}/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}_${VERSION}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && curl -fsSLO "${URL}" \
    && echo ${URL} \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubebuilder
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubebuilder" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TARGET_NAME="${BIN_NAME}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TARGET_NAME}" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && mv "${TARGET_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubectl-fzf
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && NAME="kubectl-fzf" \
    && REPO="bonnefoa/${NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${NAME}_${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "shell/kubectl_fzf.plugin.zsh" "${BIN_PATH}/${NAME}.zsh" \
    && BIN_NAME="${NAME}-server" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}" \
    && BIN_NAME="${NAME}-completion" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS k9s
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="k9s" \
    && REPO="derailed/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kube-profefe-base
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kube-profefe" \
    && REPO="profefe/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && TAR_NAME="${BIN_NAME}_v${VERSION}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && BIN_NAME="kprofefe" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && BIN_NAME="kubectl-profefe" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-profefe-base AS kprofefe
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kprofefe" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-profefe-base AS kubectl-profefe
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-profefe" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS conftest
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="conftest" \
    && REPO="open-policy-agent/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}_${VERSION}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubectl-tree
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-tree" \
    && REPO="ahmetb/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}_v${VERSION}_${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS linkerd
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="linkerd" \
    && curl -sL https://run.linkerd.io/install | sh \
    && mv ${HOME}/.linkerd2/bin/${BIN_NAME}-* "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS skaffold
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="skaffold" \
    && REPO="GoogleContainerTools/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${BIN_NAME}/releases/v${VERSION}/${BIN_NAME}-${OS}-${ARCH}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubeval
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubeval" \
    && REPO="instrumenta/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}-${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kube-linter
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kube-linter" \
    && REPO="stackrox/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}-${OS}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS helm-docs
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="helm-docs" \
    && REPO="norwoodj/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && TAR_NAME="${BIN_NAME}_${VERSION}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubectl-gadget
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="inspektor-gadget" \
    && REPO="${BIN_NAME}/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="kubectl-gadget-${OS}-${ARCH}-v${VERSION}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && BIN_NAME="kubectl-gadget" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kdash
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kdash" \
    && REPO="${BIN_NAME}-rs/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}-${OS}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubectl-rolesum
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-rolesum" \
    && REPO="Ladicle/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && TAR_NAME="${BIN_NAME}_${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${TAR_NAME}/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kubeletctl
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubeletctl" \
    && REPO="cyberark/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && FILE_NAME="${BIN_NAME}_${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${FILE_NAME}" \
    && mv "${FILE_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS istio
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="istioctl" \
    && curl -L https://istio.io/downloadIstio | sh - \
    && mv "$(ls | grep istio)/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kpt
    # && REPO="kptdev/${BIN_NAME}" \
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kpt" \
    && REPO="GoogleContainerTools/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${BIN_NAME}/releases/v${VERSION}/${BIN_NAME}-${OS}-${ARCH}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS k3d
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="k3d" \
    && REPO="rancher/${BIN_NAME}" \
    && wget -q -O - "${RAWGITHUB}/${REPO}/main/install.sh" | bash \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS kustomize
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kustomize" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
    && wget -q -O - "${RAWGITHUB}/${REPO}/master/hack/install_${BIN_NAME}.sh" | bash \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

# FROM --platform=$BUILDPLATFORM kube-base AS wasme
# RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
#     && NAME="wasme" \
#     && REPO="solo-io/wasm" \
#     && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
#     && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
#     && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
#     && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
#     && unset HEADER \
#     && BIN_NAME="${NAME}-${OS}-${ARCH}" \
#     && curl -fsSLo "${BIN_PATH}/${NAME}" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}" \
#     && chmod a+x "${BIN_PATH}/${NAME}" \
#     && upx -9 "${BIN_PATH}/${NAME}"

FROM --platform=$BUILDPLATFORM kube-base AS telepresence
RUN curl -fsSL "https://app.getambassador.io/download/tel2/${OS}/${ARCH}/nightly/telepresence" -o ${BINDIR}/telepresence \
    && chmod a+x "${BIN_PATH}/telepresence"

# FROM --platform=$BUILDPLATFORM kube-base AS pixie
# RUN set -x; cd "$(mktemp -d)" \
#     && BIN_NAME="pixie" \
#     && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${BIN_NAME}-prod-artifacts/cli/latest/cli_${OS}_${ARCH}" \
#     && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
#     && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kpango/go:latest AS golang
FROM --platform=$BUILDPLATFORM kube-base AS kube-golang-base
COPY --from=golang /opt/go /usr/local/go
COPY --from=golang /go /go
ENV GOPATH /go
ENV GOROOT /usr/local/go
ENV PATH $PATH:$GOPATH/bin:$GOROOT/bin
COPY go.env $GOROOT/go.env

FROM --platform=$BUILDPLATFORM kube-golang-base AS helmfile
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="helmfile" \
    && REPO="roboll/${BIN_NAME}" \
    &&GO111MODULE=on go install  \
      --ldflags "-s -w" --trimpath \
      "${GITHUBCOM}/${REPO}@latest" \
    && mv "${GOPATH}/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-golang-base AS kubecolor
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kubecolor" \
    && REPO="hidetatz/${BIN_NAME}" \
    &&GO111MODULE=on go install  \
      --ldflags "-s -w" --trimpath \
      "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && mv "${GOPATH}/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-golang-base AS kubeconform
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kubeconform" \
    && REPO="yannh/${BIN_NAME}" \
    &&GO111MODULE=on go install  \
      --ldflags "-s -w" --trimpath \
      "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@latest" \
    && mv "${GOPATH}/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-golang-base AS popeye
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="popeye" \
    && REPO="derailed/${BIN_NAME}" \
    &&GO111MODULE=on go install  \
      --ldflags "-s -w" --trimpath \
      "${GITHUBCOM}/${REPO}@latest" \
    && mv "${GOPATH}/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-golang-base AS kubectl-trace
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-trace" \
    && REPO="iovisor/${BIN_NAME}" \
    &&GO111MODULE=on go install  \
      --ldflags "-s -w" --trimpath \
      "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@master" \
    && mv "${GOPATH}/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-golang-base AS k8sviz
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="k8sviz" \
    && REPO="mkimuram/${BIN_NAME}" \
    &&GO111MODULE=on go install  \
      --ldflags "-s -w" --trimpath \
      "${GITHUBCOM}/${REPO}/cmd/${BIN_NAME}@master" \
    && mv "${GOPATH}/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM kube-golang-base AS kind
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kind" \
    && REPO="sigs.k8s.io/${BIN_NAME}" \
    &&GO111MODULE=on go install  \
      --ldflags "-s -w" --trimpath \
      "${REPO}/cmd/${BIN_NAME}@master" \
    && mv "${GOPATH}/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM --platform=$BUILDPLATFORM scratch AS kube
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV BIN_PATH /usr/local/bin
ENV LIB_PATH /usr/local/libexec
ENV K8S_PATH /usr/k8s/bin
ENV K8S_LIB_PATH /usr/k8s/lib

COPY --from=check-ownerreferences ${BIN_PATH}/kubectl-check-ownerreferences ${K8S_PATH}/kubectl-check-ownerreferences
COPY --from=helm ${BIN_PATH}/helm ${K8S_PATH}/helm
COPY --from=helm-docs ${BIN_PATH}/helm-docs ${K8S_PATH}/helm-docs
COPY --from=helmfile ${BIN_PATH}/helmfile ${K8S_PATH}/helmfile
COPY --from=istio ${BIN_PATH}/istioctl ${K8S_PATH}/istioctl
COPY --from=k3d ${BIN_PATH}/k3d ${K8S_PATH}/k3d
COPY --from=k8sviz ${BIN_PATH}/k8sviz ${K8S_PATH}/k8sviz
COPY --from=k9s ${BIN_PATH}/k9s ${K8S_PATH}/k9s
COPY --from=kind ${BIN_PATH}/kind ${K8S_PATH}/kind
COPY --from=kprofefe ${BIN_PATH}/kprofefe ${K8S_PATH}/kprofefe
COPY --from=kpt ${BIN_PATH}/kpt ${K8S_PATH}/kpt
COPY --from=kdash ${BIN_PATH}/kdash ${K8S_PATH}/kdash
COPY --from=krew ${BIN_PATH}/kubectl-krew ${K8S_PATH}/kubectl-krew
COPY --from=krew /root/.krew/index $/root/.krew/index
COPY --from=kube-linter ${BIN_PATH}/kube-linter ${K8S_PATH}/kube-linter
COPY --from=kube-linter ${BIN_PATH}/kube-linter ${K8S_PATH}/kubectl-lint
COPY --from=kubebox ${BIN_PATH}/kubebox ${K8S_PATH}/kubebox
COPY --from=kubebuilder ${BIN_PATH}/kubebuilder ${K8S_PATH}/kubebuilder
COPY --from=kubecolor ${BIN_PATH}/kubecolor ${K8S_PATH}/kubecolor
COPY --from=kubeconform ${BIN_PATH}/kubeconform ${K8S_PATH}/kubeconform
COPY --from=kubectl ${BIN_PATH}/kubectl ${K8S_PATH}/kubectl
COPY --from=kubectl-fzf ${BIN_PATH}/kubectl-fzf-server ${K8S_PATH}/kubectl-fzf-server
COPY --from=kubectl-fzf ${BIN_PATH}/kubectl-fzf-completion ${K8S_PATH}/kubectl-fzf-completion
COPY --from=kubectl-fzf ${BIN_PATH}/kubectl-fzf.zsh ${K8S_PATH}/kubectl-fzf.zsh
COPY --from=kubectl-gadget ${BIN_PATH}/kubectl-gadget ${K8S_PATH}/kubectl-gadget
COPY --from=kubectl-profefe ${BIN_PATH}/kubectl-profefe ${K8S_PATH}/kubectl-profefe
COPY --from=kubectl-rolesum ${BIN_PATH}/kubectl-rolesum ${K8S_PATH}/kubectl-rolesum
COPY --from=kubectl-trace ${BIN_PATH}/kubectl-trace ${K8S_PATH}/kubectl-trace
COPY --from=kubectl-tree ${BIN_PATH}/kubectl-tree ${K8S_PATH}/kubectl-tree
COPY --from=kubectx ${BIN_PATH}/kubectx ${K8S_PATH}/kubectx
COPY --from=kubefwd ${BIN_PATH}/kubefwd ${K8S_PATH}/kubectl-fwd
COPY --from=kubefwd ${BIN_PATH}/kubefwd ${K8S_PATH}/kubefwd
COPY --from=kubeletctl ${BIN_PATH}/kubeletctl ${K8S_PATH}/kubeletctl
COPY --from=kubens ${BIN_PATH}/kubens ${K8S_PATH}/kubens
COPY --from=kubeval ${BIN_PATH}/kubeval ${K8S_PATH}/kubeval
COPY --from=kustomize ${BIN_PATH}/kustomize ${K8S_PATH}/kustomize
COPY --from=linkerd ${BIN_PATH}/linkerd ${K8S_PATH}/linkerd
# COPY --from=pixie ${BIN_PATH}/pixie ${K8S_PATH}/pixie
COPY --from=popeye ${BIN_PATH}/popeye ${K8S_PATH}/popeye
COPY --from=skaffold ${BIN_PATH}/skaffold ${K8S_PATH}/skaffold
COPY --from=stern ${BIN_PATH}/stern ${K8S_PATH}/stern
COPY --from=telepresence ${BIN_PATH}/telepresence ${K8S_PATH}/telepresence
# COPY --from=wasme ${BIN_PATH}/wasme ${K8S_PATH}/wasme
