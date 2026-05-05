# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS k8s-base

ARG TARGETOS
ARG TARGETARCH

RUN mkdir -p "${BIN_PATH}"

FROM k8s-base AS kubectl
RUN set -x; cd "$(mktemp -d)" \
    && BIN_NAME="kubectl" \
    && VERSION="$(curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL ${GOOGLE}/kubernetes-release/release/stable.txt)" \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${VERSION}" >&2; \
            exit 1; \
        } \
    && URL="${GOOGLE}/kubernetes-release/release/${VERSION}/bin/${OS}/${ARCH}/${BIN_NAME}" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${BIN_PATH}/${BIN_NAME}" "${URL}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && "${BIN_PATH}/${BIN_NAME}" version --client
    # upx is intentionally skipped: kubectl uses Go assembly (CGO+plugins) that upx corrupts

FROM k8s-base AS helm
RUN --mount=type=secret,id=gat \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="helm" \
    && REPO="helm/helm" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] && [ "${VERSION}" != "null" ] \
        || { echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; exit 1; } \
    && TAR_NAME="${BIN_NAME}-v${VERSION}-${OS}-${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "https://get.helm.sh/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${OS}-${ARCH}/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS kubefwd
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubefwd" \
    && REPO="txn2/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; esac \
    && OS_CAP=$(case "${OS}" in linux) echo "Linux" ;; darwin) echo "Darwin" ;; *) echo "${OS}" ;; esac) \
    && TAR_NAME="${BIN_NAME}_${OS_CAP}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS kubectx
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && REPO="ahmetb/kubectx" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; esac \
    && BIN_CTX="kubectx" \
    && TAR_CTX="${BIN_CTX}_v${VERSION}_${OS}_${ARCH}" \
    && URL_CTX="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_CTX}.tar.gz" \
    && echo ${URL_CTX} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL_CTX}" \
    && tar -zxvf "${TAR_CTX}.tar.gz" \
    && mv "${BIN_CTX}" "${BIN_PATH}/${BIN_CTX}" \
    && (upx --best "${BIN_PATH}/${BIN_CTX}" || true) \
    && BIN_NS="kubens" \
    && TAR_NS="${BIN_NS}_v${VERSION}_${OS}_${ARCH}" \
    && URL_NS="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NS}.tar.gz" \
    && echo ${URL_NS} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL_NS}" \
    && tar -zxvf "${TAR_NS}.tar.gz" \
    && mv "${BIN_NS}" "${BIN_PATH}/${BIN_NS}" \
    && (upx --best "${BIN_PATH}/${BIN_NS}" || true)


FROM k8s-base AS krew
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="krew" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="${BIN_NAME}-${OS}_${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}.yaml" \
    && "${PWD}/${TAR_NAME}" install --manifest="${BIN_NAME}.yaml" --archive="${TAR_NAME}.tar.gz" \
    && BIN_NAME="kubectl-krew" \
    && "/root/.krew/bin/${BIN_NAME}" update \
    && mv "/root/.krew/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}"

FROM k8s-base AS kubebox
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubebox" \
    && REPO="astefanutti/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-${OS}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && upx --best "${BIN_PATH}/${BIN_NAME}" || true

FROM k8s-base AS stern
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="stern" \
    && REPO="${BIN_NAME}/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="${BIN_NAME}_${VERSION}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL}" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)

FROM k8s-base AS kubebuilder
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubebuilder" \
    && REPO="kubernetes-sigs/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TARGET_NAME="${BIN_NAME}_${OS}_${ARCH}" \
    && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TARGET_NAME}" \
    && echo ${URL} \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${URL}" \
    && mv "${TARGET_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS k9s
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="k9s" \
    && REPO="derailed/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && OS_CAP=$(case "${OS}" in linux) echo "Linux" ;; darwin) echo "Darwin" ;; *) echo "${OS}" ;; esac) \
    && TAR_NAME="${BIN_NAME}_${OS_CAP}_${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS conftest
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="conftest" \
    && REPO="open-policy-agent/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; arm64|aarch64) ARCH=${AARCH} ;; esac \
    && OS_CAP=$(case "${OS}" in linux) echo "Linux" ;; darwin) echo "Darwin" ;; *) echo "${OS}" ;; esac) \
    && TAR_NAME="${BIN_NAME}_${VERSION}_${OS_CAP}_${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)

FROM k8s-base AS kubectl-tree
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-tree" \
    && REPO="ahmetb/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="${BIN_NAME}_v${VERSION}_${OS}_${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS linkerd
RUN --mount=type=secret,id=gat \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="linkerd" \
    && REPO="linkerd/linkerd2" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/releases?per_page=100" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/releases?per_page=100" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r '[.[] | select(.tag_name | startswith("stable"))][0].tag_name' | sed 's/^stable-//') \
    && [ -n "${VERSION}" ] && [ "${VERSION}" != "null" ] \
        || { echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; exit 1; } \
    && ASSET="linkerd2-cli-stable-${VERSION}-${OS}-${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GITHUB}/${REPO}/${RELEASE_DL}/stable-${VERSION}/${ASSET}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS skaffold
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="skaffold" \
    && REPO="GoogleContainerTools/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GOOGLE}/${BIN_NAME}/releases/v${VERSION}/${BIN_NAME}-${OS}-${ARCH}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS kube-linter
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kube-linter" \
    && REPO="stackrox/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="${BIN_NAME}-${OS}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true) \

    && cp "${BIN_PATH}/${BIN_NAME}" "${BIN_PATH}/kubectl-lint"

FROM k8s-base AS helm-docs
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="helm-docs" \
    && REPO="norwoodj/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; esac \
    && OS_CAP=$(case "${OS}" in linux) echo "Linux" ;; darwin) echo "Darwin" ;; *) echo "${OS}" ;; esac) \
    && TAR_NAME="${BIN_NAME}_${VERSION}_${OS_CAP}_${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS kubectl-gadget
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="inspektor-gadget" \
    && REPO="${BIN_NAME}/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="kubectl-gadget-${OS}-${ARCH}-v${VERSION}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && BIN_NAME="kubectl-gadget" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS kdash
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kdash" \
    && REPO="${BIN_NAME}-rs/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="${BIN_NAME}-${OS}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && upx --best "${BIN_PATH}/${BIN_NAME}" || true

FROM k8s-base AS kubectl-rolesum
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="kubectl-rolesum" \
    && REPO="Ladicle/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && TAR_NAME="${BIN_NAME}_${OS}-${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${TAR_NAME}/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS istio
RUN --mount=type=secret,id=gat \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="istioctl" \
    && REPO="istio/istio" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] && [ "${VERSION}" != "null" ] \
        || { echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; exit 1; } \
    && case "${ARCH}" in amd64) ISTIO_ARCH="amd64" ;; arm64|aarch64) ISTIO_ARCH="arm64" ;; *) ISTIO_ARCH="amd64" ;; esac \
    && TAR_NAME="${BIN_NAME}-${VERSION}-${OS}-${ISTIO_ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && mv "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS k3d
RUN --mount=type=secret,id=gat \
set -x && cd "$(mktemp -d)" \
    && BIN_NAME="k3d" \
    && REPO="k3d-io/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/tags" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/tags" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r '[.[] | select(.name | contains("-") | not)][0].name' | sed 's/^v//') \
    && [ -n "${VERSION}" ] \
    && [ "${VERSION}" != "null" ] \
        || { \
            echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
            exit 1; \
        } \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo "${BIN_PATH}/${BIN_NAME}" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-${OS}-${ARCH}" \
    && chmod a+x "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)


FROM k8s-base AS telepresence
RUN curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo ${BIN_PATH}/telepresence  "${GITHUB}/telepresenceio/telepresence/${RELEASE_LATEST}/download/telepresence-${OS}-${ARCH}" \
    && chmod a+x "${BIN_PATH}/telepresence" \
    && upx --best "${BIN_PATH}/telepresence" || true

FROM k8s-base AS k8s-bins
ENV K8S_PATH=/usr/k8s/bin \
    K8S_LIB_PATH=/usr/k8s/lib

COPY --link --from=helm ${BIN_PATH}/helm ${K8S_PATH}/helm
COPY --link --from=helm-docs ${BIN_PATH}/helm-docs ${K8S_PATH}/helm-docs
COPY --link --from=istio ${BIN_PATH}/istioctl ${K8S_PATH}/istioctl
COPY --link --from=k3d ${BIN_PATH}/k3d ${K8S_PATH}/k3d
COPY --link --from=k9s ${BIN_PATH}/k9s ${K8S_PATH}/k9s
COPY --link --from=kdash ${BIN_PATH}/kdash ${K8S_PATH}/kdash
COPY --link --from=krew ${BIN_PATH}/kubectl-krew ${K8S_PATH}/kubectl-krew
COPY --link --from=krew /root/.krew/index /root/.krew/index
COPY --link --from=kube-linter ${BIN_PATH}/kube-linter ${K8S_PATH}/kube-linter
COPY --link --from=kube-linter ${BIN_PATH}/kubectl-lint ${K8S_PATH}/kubectl-lint
COPY --link --from=kubebox ${BIN_PATH}/kubebox ${K8S_PATH}/kubebox
COPY --link --from=kubebuilder ${BIN_PATH}/kubebuilder ${K8S_PATH}/kubebuilder
COPY --link --from=kubectl ${BIN_PATH}/kubectl ${K8S_PATH}/kubectl
COPY --link --from=kubectl-gadget ${BIN_PATH}/kubectl-gadget ${K8S_PATH}/kubectl-gadget
COPY --link --from=kubectl-rolesum ${BIN_PATH}/kubectl-rolesum ${K8S_PATH}/kubectl-rolesum
COPY --link --from=kubectl-tree ${BIN_PATH}/kubectl-tree ${K8S_PATH}/kubectl-tree
COPY --link --from=kubectx ${BIN_PATH}/kubectx ${K8S_PATH}/kubectx
COPY --link --from=kubefwd ${BIN_PATH}/kubefwd ${K8S_PATH}/kubectl-fwd
COPY --link --from=kubefwd ${BIN_PATH}/kubefwd ${K8S_PATH}/kubefwd
COPY --link --from=kubectx ${BIN_PATH}/kubens ${K8S_PATH}/kubens
COPY --link --from=linkerd ${BIN_PATH}/linkerd ${K8S_PATH}/linkerd
COPY --link --from=skaffold ${BIN_PATH}/skaffold ${K8S_PATH}/skaffold
COPY --link --from=stern ${BIN_PATH}/stern ${K8S_PATH}/stern
COPY --link --from=telepresence ${BIN_PATH}/telepresence ${K8S_PATH}/telepresence

FROM scratch AS kube
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV K8S_PATH=/usr/k8s/bin \
    K8S_LIB_PATH=/usr/k8s/lib

COPY --link --from=k8s-bins ${K8S_PATH} ${K8S_PATH}
COPY --link --from=k8s-bins /root/.krew/index /root/.krew/index
