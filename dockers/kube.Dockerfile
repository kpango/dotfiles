# syntax = docker/dockerfile:latest
FROM kpango/base:latest AS kube-base

ARG TARGETOS
ARG TARGETARCH
ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV AARCH=aarch64
ENV XARCH=x86_64
ENV GITHUBCOM=github.com
ENV GITHUB=https://${GITHUBCOM}
ENV API_GITHUB=https://api.github.com/repos
ENV RAWGITHUB=https://raw.githubusercontent.com
ENV GOOGLE=https://storage.googleapis.com
ENV RELEASE_DL=releases/download
ENV RELEASE_LATEST=releases/latest
ENV LOCAL=/usr/local
ENV BIN_PATH=${LOCAL}/bin

RUN mkdir -p "${BIN_PATH}"

FROM kube-base AS kubectl
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kubectl" \
    && VERSION="$(curl -fsSL ${GOOGLE}/kubernetes-release/release/stable.txt)" \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${VERSION}" >&2; exit 1; } \
    && URL="${GOOGLE}/kubernetes-release/release/${VERSION}/bin/${OS}/${ARCH}/${BIN_NAME}" \
    && echo ${URL} \
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${URL}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && "${BIN_PATH}/${BIN_NAME}" version --client
    # && upx -9 "${BIN_PATH}/${BIN_NAME}" \

FROM kube-base AS helm
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && curl -fsSLGH "${HEADER}" "${RAWGITHUB}/helm/helm/main/scripts/get-helm-3" | bash \
    && unset HEADER \
    && BIN_NAME="helm" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubefwd
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubefwd" \
    && REPO="txn2/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubectx
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectx" \
    && REPO="ahmetb/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_v${VERSION}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubens
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectx" \
    && REPO="ahmetb/${BIN_NAME}" \
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
    && BIN_NAME="kubens" \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && TAR_NAME="${BIN_NAME}_v${VERSION}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS krew
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="krew" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}-${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}.yaml" \
    && "${PWD}/${TAR_NAME}" install --manifest="${BIN_NAME}.yaml" --archive="${TAR_NAME}.tar.gz" \
    && BIN_NAME="kubectl-krew" \
    && "/root/.krew/bin/${BIN_NAME}" update \
    && mv "/root/.krew/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubebox
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubebox" \
    && REPO="astefanutti/${BIN_NAME}" \
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
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-${OS}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS stern
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="stern" \
    && REPO="${BIN_NAME}/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_${VERSION}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && curl -fsSLO "${URL}" \
    && echo ${URL} \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubebuilder
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubebuilder" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
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
    && TARGET_NAME="${BIN_NAME}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TARGET_NAME}" \
    && echo ${URL} \
    && curl -fsSLO "${URL}" \
    && mv "${TARGET_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS k9s
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="k9s" \
    && REPO="derailed/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS conftest
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="conftest" \
    && REPO="open-policy-agent/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_${VERSION}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubectl-tree
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-tree" \
    && REPO="ahmetb/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_v${VERSION}_${OS}_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS linkerd
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="linkerd" \
    && curl -fsSL https://run.linkerd.io/install | sh \
    && mv ${HOME}/.linkerd2/bin/${BIN_NAME}-* "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS skaffold
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="skaffold" \
    && REPO="GoogleContainerTools/${BIN_NAME}" \
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
    && curl -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${BIN_NAME}/releases/v${VERSION}/${BIN_NAME}-${OS}-${ARCH}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kube-linter
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kube-linter" \
    && REPO="stackrox/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}-${OS}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS helm-docs
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="helm-docs" \
    && REPO="norwoodj/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_${VERSION}_$(echo ${OS} | sed 's/.*/\u&/')_${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubectl-gadget
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="inspektor-gadget" \
    && REPO="${BIN_NAME}/${BIN_NAME}" \
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
    && TAR_NAME="kubectl-gadget-${OS}-${ARCH}-v${VERSION}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && BIN_NAME="kubectl-gadget" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kdash
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kdash" \
    && REPO="${BIN_NAME}-rs/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}-${OS}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS kubectl-rolesum
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-rolesum" \
    && REPO="Ladicle/${BIN_NAME}" \
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
    && TAR_NAME="${BIN_NAME}_${OS}-${ARCH}" \
    && curl -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${TAR_NAME}/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS istio
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="istioctl" \
    && curl -fsSL https://istio.io/downloadIstio | sh - \
    && mv "$(ls | grep istio)/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS k3d
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && BIN_NAME="k3d" \
    && REPO="rancher/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && curl -fsSLGH "${HEADER}" "${RAWGITHUB}/${REPO}/main/install.sh" | bash \
    && unset HEADER \
    && upx -9 "${BIN_PATH}/${BIN_NAME}"

FROM kube-base AS telepresence
RUN curl -fsSLo ${BIN_PATH}/telepresence "https://app.getambassador.io/download/tel2/${OS}/${ARCH}/nightly/telepresence" \
    && chmod a+x "${BIN_PATH}/telepresence"

FROM scratch AS kube
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV BIN_PATH=/usr/local/bin
ENV LIB_PATH=/usr/local/libexec
ENV K8S_PATH=/usr/k8s/bin
ENV K8S_LIB_PATH=/usr/k8s/lib

COPY --from=helm ${BIN_PATH}/helm ${K8S_PATH}/helm
COPY --from=helm-docs ${BIN_PATH}/helm-docs ${K8S_PATH}/helm-docs
COPY --from=istio ${BIN_PATH}/istioctl ${K8S_PATH}/istioctl
COPY --from=k3d ${BIN_PATH}/k3d ${K8S_PATH}/k3d
COPY --from=k9s ${BIN_PATH}/k9s ${K8S_PATH}/k9s
COPY --from=kdash ${BIN_PATH}/kdash ${K8S_PATH}/kdash
COPY --from=krew ${BIN_PATH}/kubectl-krew ${K8S_PATH}/kubectl-krew
COPY --from=krew /root/.krew/index $/root/.krew/index
COPY --from=kube-linter ${BIN_PATH}/kube-linter ${K8S_PATH}/kube-linter
COPY --from=kube-linter ${BIN_PATH}/kube-linter ${K8S_PATH}/kubectl-lint
COPY --from=kubebox ${BIN_PATH}/kubebox ${K8S_PATH}/kubebox
COPY --from=kubebuilder ${BIN_PATH}/kubebuilder ${K8S_PATH}/kubebuilder
COPY --from=kubectl ${BIN_PATH}/kubectl ${K8S_PATH}/kubectl
COPY --from=kubectl-gadget ${BIN_PATH}/kubectl-gadget ${K8S_PATH}/kubectl-gadget
COPY --from=kubectl-rolesum ${BIN_PATH}/kubectl-rolesum ${K8S_PATH}/kubectl-rolesum
COPY --from=kubectl-tree ${BIN_PATH}/kubectl-tree ${K8S_PATH}/kubectl-tree
COPY --from=kubectx ${BIN_PATH}/kubectx ${K8S_PATH}/kubectx
COPY --from=kubefwd ${BIN_PATH}/kubefwd ${K8S_PATH}/kubectl-fwd
COPY --from=kubefwd ${BIN_PATH}/kubefwd ${K8S_PATH}/kubefwd
COPY --from=kubens ${BIN_PATH}/kubens ${K8S_PATH}/kubens
COPY --from=linkerd ${BIN_PATH}/linkerd ${K8S_PATH}/linkerd
COPY --from=skaffold ${BIN_PATH}/skaffold ${K8S_PATH}/skaffold
COPY --from=stern ${BIN_PATH}/stern ${K8S_PATH}/stern
COPY --from=telepresence ${BIN_PATH}/telepresence ${K8S_PATH}/telepresence
