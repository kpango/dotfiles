# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS k8s-base

ARG TARGETARCH

RUN mkdir -p "${BIN_PATH}"

FROM k8s-base AS kubectl
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubectl \
        VERSION_URL='$(GOOGLE)/kubernetes-release/release/stable.txt' \
        VER_IN_NAME=0 INCLUDE_ARCH=0 EXT= \
        URL_TEMPLATE='$(GOOGLE)/kubernetes-release/release/v$(VERSION)/bin/$(OS)/$(ARCH)/$(APP_NAME)' \
        UPX=1 \
    && "${BIN_PATH}/kubectl" version --client

FROM k8s-base AS helm
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=helm REPO='helm/$(APP_NAME)' VER_TAG=v \
        DL_BASE_URL='https://get.helm.sh' \
        BIN_SUBDIR='$(OS)-$(ARCH)' UPX=1


FROM k8s-base AS kubefwd
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubefwd REPO='txn2/$(APP_NAME)' \
        SEP=_ VER_IN_NAME=0 OS_ALIAS='$(OS_CAP)' ARCH_ALIAS='$(ARCH_X86)' UPX=1


FROM k8s-base AS kubectx
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubectx REPO='ahmetb/$(APP_NAME)' \
        BINS='$(APP_NAME) kubens' SEP=_ VER_TAG=v UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/{BIN}_v$(VERSION)_$(OS)_$(ARCH_X86).tar.gz'


FROM k8s-base AS krew
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    set -x && cd "$(mktemp -d)" \
    && REPO="kubernetes-sigs/krew" \
    && VERSION="$(make --no-print-directory -f /mk/download.mk get-version REPO="${REPO}")" \
    && TAR_NAME="krew-${OS}_${ARCH}" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} \
        -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/krew.yaml" \
    && "${PWD}/${TAR_NAME}" install --manifest="krew.yaml" --archive="${TAR_NAME}.tar.gz" \
    && BIN_NAME="kubectl-krew" \
    && "/root/.krew/bin/${BIN_NAME}" update \
    && mv "/root/.krew/bin/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best ${BIN_PATH}/kubectl-krew 2>/dev/null || true)

FROM k8s-base AS kubebox
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubebox REPO='astefanutti/$(APP_NAME)' EXT= UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/$(APP_NAME)$(if $(filter arm64,$(ARCH)),-arm,-$(OS))'

FROM k8s-base AS stern
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=stern SEP=_ UPX=1

FROM k8s-base AS kubebuilder
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubebuilder REPO='kubernetes-sigs/$(APP_NAME)' \
        SEP=_ VER_IN_NAME=0 EXT= UPX=1


FROM k8s-base AS k9s
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=k9s REPO='derailed/$(APP_NAME)' \
        SEP=_ VER_IN_NAME=0 OS_ALIAS='$(OS_CAP)' UPX=1


FROM k8s-base AS conftest
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=conftest REPO='open-policy-agent/$(APP_NAME)' \
        SEP=_ OS_ALIAS='$(OS_CAP)' ARCH_ALIAS='$(ARCH_X86)' UPX=1

FROM k8s-base AS kubectl-tree
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubectl-tree REPO='ahmetb/$(APP_NAME)' \
        SEP=_ VER_TAG=v UPX=1


FROM k8s-base AS linkerd
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=linkerd REPO=linkerd/linkerd2 EXT= UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/$(VERSION)/linkerd2-cli-$(VERSION)-$(OS)-$(ARCH)'


FROM k8s-base AS skaffold
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=skaffold REPO='GoogleContainerTools/$(APP_NAME)' \
        DL_BASE_URL='$(GOOGLE)/skaffold/releases/v$(VERSION)' \
        VER_IN_NAME=0 EXT= UPX=1


FROM k8s-base AS kube-linter
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kube-linter REPO='stackrox/$(APP_NAME)' UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/$(APP_NAME)-$(OS)$(if $(filter arm64,$(ARCH)),_arm64,).tar.gz' \
    && cp "${BIN_PATH}/kube-linter" "${BIN_PATH}/kubectl-lint"

FROM k8s-base AS helm-docs
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=helm-docs REPO='norwoodj/$(APP_NAME)' \
        SEP=_ OS_ALIAS='$(OS_CAP)' ARCH_ALIAS='$(ARCH_X86)' UPX=1


FROM k8s-base AS kubectl-gadget
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubectl-gadget REPO='inspektor-gadget/inspektor-gadget' UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/$(APP_NAME)-$(OS)-$(ARCH)-v$(VERSION).tar.gz'


FROM k8s-base AS kubectl-rolesum
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubectl-rolesum REPO='Ladicle/$(APP_NAME)' \
        SEP=_ OS_ARCH_SEP=- VER_IN_NAME=0 UPX=1


FROM k8s-base AS istio
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=istio BIN=istioctl REPO='istio/$(APP_NAME)' \
        URL_VER_TAG= UPX=1


FROM k8s-base AS k3d
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=k3d REPO='k3d-io/$(APP_NAME)' \
        VER_IN_NAME=0 EXT= UPX=1


FROM k8s-base AS telepresence
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=telepresence REPO='telepresenceio/$(APP_NAME)' \
        VER_IN_NAME=0 EXT= UPX=1

FROM k8s-base AS k8s-bins
ENV K8S_PATH=/usr/k8s/bin \
    K8S_LIB_PATH=/usr/k8s/lib

COPY --link --from=helm ${BIN_PATH}/helm ${K8S_PATH}/helm
COPY --link --from=helm-docs ${BIN_PATH}/helm-docs ${K8S_PATH}/helm-docs
COPY --link --from=istio ${BIN_PATH}/istioctl ${K8S_PATH}/istioctl
COPY --link --from=k3d ${BIN_PATH}/k3d ${K8S_PATH}/k3d
COPY --link --from=k9s ${BIN_PATH}/k9s ${K8S_PATH}/k9s
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
