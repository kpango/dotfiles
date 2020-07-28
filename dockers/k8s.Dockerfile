FROM kpango/dev-base:latest AS kube-base

ENV ARCH amd64
ENV OS linux
ENV GITHUB https://github.com
ENV GOOGLE https://storage.googleapis.com
ENV RELEASE_DL releases/download
ENV RELEASE_LATEST releases/latest
ENV LOCAL /usr/local
ENV BIN_PATH ${LOCAL}/bin
ENV TELEPRESENCE_VERSION 0.105

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.8 \
    python3-setuptools \
    python3-pip \
    python3-venv \
    && mkdir -p ${BIN_PATH}

FROM kube-base AS kubectl
RUN set -x; cd "$(mktemp -d)" \
    && mkdir -p ${BIN_PATH} \
    && curl -fsSLo ${BIN_PATH}/kubectl "${GOOGLE}/kubernetes-release/release/$(curl -s ${GOOGLE}/kubernetes-release/release/stable.txt)/bin/${OS}/${ARCH}/kubectl" \
    && chmod a+x ${BIN_PATH}/kubectl \
    && ${BIN_PATH}/kubectl version --client

FROM kube-base AS helm
RUN set -x; cd "$(mktemp -d)" \
    && curl "https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3" | bash

FROM kube-base AS helmfile
RUN set -x; cd "$(mktemp -d)" \
    && HELMFILE_VERSION="$(curl --silent ${GITHUB}/roboll/helmfile/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLo ${BIN_PATH}/helmfile "${GITHUB}/roboll/helmfile/${RELEASE_DL}/v${HELMFILE_VERSION}/helmfile_${OS}_${ARCH}" \
    && chmod a+x ${BIN_PATH}/helmfile

FROM kube-base AS kubectx
RUN set -x; cd "$(mktemp -d)" \
    && git clone "${GITHUB}/ahmetb/kubectx" /opt/kubectx \
    && mv /opt/kubectx/kubectx ${BIN_PATH}/kubectx \
    && mv /opt/kubectx/kubens ${BIN_PATH}/kubens

FROM kube-base AS krew
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "${GITHUB}/kubernetes-sigs/krew/${RELEASE_DL}/$(curl --silent ${GITHUB}/kubernetes-sigs/krew/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#')/krew.{tar.gz,yaml}" \
    && tar zxvf krew.tar.gz \
    && ./krew-"${OS}_${ARCH}" install --manifest=krew.yaml --archive=krew.tar.gz

FROM kube-base AS kubebox
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLo ${BIN_PATH}/kubebox "${GITHUB}/astefanutti/kubebox/${RELEASE_DL}/$(curl --silent ${GITHUB}/astefanutti/kubebox/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#')/kubebox-${OS}" \
    && chmod a+x ${BIN_PATH}/kubebox

FROM kube-base AS stern
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLo ${BIN_PATH}/stern "${GITHUB}/wercker/stern/${RELEASE_DL}/$(curl --silent ${GITHUB}/wercker/stern/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#')/stern_${OS}_${ARCH}" \
    && chmod a+x ${BIN_PATH}/stern

FROM kube-base AS kubebuilder
RUN set -x; cd "$(mktemp -d)" \
    && KUBEBUILDER_VERSION="$(curl --silent ${GITHUB}/kubernetes-sigs/kubebuilder/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/kubernetes-sigs/kubebuilder/${RELEASE_DL}/v${KUBEBUILDER_VERSION}/kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz \
    && mv kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}/bin/* ${BIN_PATH}/

FROM kube-base AS kind
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLo ${BIN_PATH}/kind "${GITHUB}/kubernetes-sigs/kind/${RELEASE_DL}/$(curl --silent ${GITHUB}/kubernetes-sigs/kind/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#')/kind-${OS}-${ARCH}" \
    && chmod a+x ${BIN_PATH}/kind

FROM kube-base AS kubectl-fzf
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "${GITHUB}/bonnefoa/kubectl-fzf/${RELEASE_DL}/$(curl --silent ${GITHUB}/bonnefoa/kubectl-fzf/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#')/kubectl-fzf_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubectl-fzf_${OS}_${ARCH}.tar.gz \
    && mv cache_builder ${BIN_PATH}/cache_builder

FROM kube-base AS k9s
RUN set -x; cd "$(mktemp -d)" \
    && K9S_VERSION="$(curl --silent ${GITHUB}/derailed/k9s/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/derailed/k9s/${RELEASE_DL}/v${K9S_VERSION}/k9s_Linux_x86_64.tar.gz" \
    && tar -zxvf k9s_Linux_x86_64.tar.gz \
    && mv k9s ${BIN_PATH}/k9s

FROM kube-base AS telepresence
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "${GITHUB}/telepresenceio/telepresence/archive/${TELEPRESENCE_VERSION}.tar.gz" \
    && tar -zxvf ${TELEPRESENCE_VERSION}.tar.gz \
    && env PREFIX=${LOCAL} telepresence-${TELEPRESENCE_VERSION}/install.sh

FROM kube-base AS kube-profefe
RUN set -x; cd "$(mktemp -d)" \
    && KUBE_PROFEFE_VERSION="$(curl --silent ${GITHUB}/profefe/kube-profefe/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/profefe/kube-profefe/${RELEASE_DL}/v${KUBE_PROFEFE_VERSION}/kube-profefe_v${KUBE_PROFEFE_VERSION}_Linux_x86_64.tar.gz" \
    && tar -zxvf "kube-profefe_v${KUBE_PROFEFE_VERSION}_Linux_x86_64.tar.gz" \
    && mv kprofefe ${BIN_PATH}/kprofefe \
    && mv kubectl-profefe ${BIN_PATH}/kubectl-profefe

FROM kube-base AS kube-tree
RUN set -x; cd "$(mktemp -d)" \
    && KUBETREE_VERSION="$(curl --silent ${GITHUB}/ahmetb/kubectl-tree/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO ${GITHUB}/ahmetb/kubectl-tree/${RELEASE_DL}/v${KUBETREE_VERSION}/kubectl-tree_v${KUBETREE_VERSION}_${OS}_${ARCH}.tar.gz \
    && tar -zxvf "kubectl-tree_v${KUBETREE_VERSION}_${OS}_${ARCH}.tar.gz" \
    && mv kubectl-tree ${BIN_PATH}/kubectl-tree

FROM kube-base AS linkerd
RUN set -x; cd "$(mktemp -d)" \
    && curl -sL https://run.linkerd.io/install | sh \
    && mv ${HOME}/.linkerd2/bin/linkerd-* ${BIN_PATH}/linkerd

FROM kube-base AS octant
RUN set -x; cd "$(mktemp -d)" \
    && OCTANT_VERSION="$(curl --silent ${GITHUB}/vmware-tanzu/octant/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/vmware-tanzu/octant/${RELEASE_DL}/v${OCTANT_VERSION}/octant_${OCTANT_VERSION}_Linux-64bit.tar.gz" \
    && tar -zxvf "octant_${OCTANT_VERSION}_Linux-64bit.tar.gz" \
    && mv octant_${OCTANT_VERSION}_Linux-64bit/octant ${BIN_PATH}/octant

FROM kube-base AS skaffold
RUN set -x; cd "$(mktemp -d)" \
    && SKAFFOLD_VERSION="$(curl --silent ${GITHUB}/GoogleContainerTools/skaffold/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSL -o ${BIN_PATH}/skaffold "${GOOGLE}/skaffold/releases/v${SKAFFOLD_VERSION}/skaffold-${OS}-${ARCH}" \
    && chmod +x ${BIN_PATH}/skaffold

FROM kube-base AS kubeval
RUN set -x; cd "$(mktemp -d)" \
    && KUBEVAL_VERSION="$(curl --silent ${GITHUB}/instrumenta/kubeval/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO ${GITHUB}/instrumenta/kubeval/${RELEASE_DL}/${KUBEVAL_VERSION}/kubeval-${OS}-${ARCH}.tar.gz \
    && tar -zxvf kubeval-${OS}-${ARCH}.tar.gz \
    && mv kubeval ${BIN_PATH}/kubeval

FROM kube-base AS helm-docs
RUN set -x; cd "$(mktemp -d)" \
    && HELM_DOCS_VERSION="$(curl --silent ${GITHUB}/norwoodj/helm-docs/${RELEASE_LATEST} | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO ${GITHUB}/norwoodj/helm-docs/${RELEASE_DL}/v${HELM_DOCS_VERSION}/helm-docs_${HELM_DOCS_VERSION}_Linux_x86_64.tar.gz \
    && tar -zxvf helm-docs_${HELM_DOCS_VERSION}_Linux_x86_64.tar.gz \
    && mv helm-docs ${BIN_PATH}/helm-docs

FROM kube-base AS istio
RUN set -x; cd "$(mktemp -d)" \
    & curl -L https://istio.io/downloadIstio | sh - \
    && mv "$(ls | grep istio)/bin/istioctl" ${BIN_PATH}/istioctl

FROM kube-base AS kpt
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLo ${BIN_PATH}/kpt ${GOOGLE}/kpt-dev/latest/${OS}_${ARCH}/kpt \
    && chmod a+x ${BIN_PATH}/kpt


FROM kube-base AS kustomize
RUN set -x; cd "$(mktemp -d)" \
    && curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases | \
    grep browser_download | \
    grep ${OS}_${ARCH} | \
    grep kustomize_v  | \
    head -n1 | \
    cut -d "\"" -f 4 | \
    xargs curl -fsSLo kustomize.tar.gz \
    && tar -zxvf kustomize.tar.gz \
    && mv kustomize ${BIN_PATH}/kustomize

FROM scratch AS kube

ENV BIN_PATH /usr/local/bin
ENV K8S_PATH /usr/k8s/bin
COPY --from=helm ${BIN_PATH}/helm ${K8S_PATH}/helm
COPY --from=helm-docs ${BIN_PATH}/helm-docs ${K8S_PATH}/helm-docs
COPY --from=helmfile ${BIN_PATH}/helmfile ${K8S_PATH}/helmfile
COPY --from=istio ${BIN_PATH}/istioctl ${K8S_PATH}/istioctl
COPY --from=k9s ${BIN_PATH}/k9s ${K8S_PATH}/k9s
COPY --from=kind ${BIN_PATH}/kind ${K8S_PATH}/kind
COPY --from=kpt ${BIN_PATH}/kpt ${K8S_PATH}/kpt
COPY --from=krew /root/.krew/bin/kubectl-krew ${K8S_PATH}/kubectl-krew
COPY --from=kube-profefe ${BIN_PATH}/kprofefe ${K8S_PATH}/kprofefe
COPY --from=kube-profefe ${BIN_PATH}/kubectl-profefe ${K8S_PATH}/kubectl-profefe
COPY --from=kube-tree ${BIN_PATH}/kubectl-tree ${K8S_PATH}/kubectl-tree
COPY --from=kubebox ${BIN_PATH}/kubebox ${K8S_PATH}/kubebox
COPY --from=kubebuilder ${BIN_PATH}/kubebuilder ${K8S_PATH}/kubebuilder
COPY --from=kubectl ${BIN_PATH}/kubectl ${K8S_PATH}/kubectl
COPY --from=kubectl-fzf ${BIN_PATH}/cache_builder ${K8S_PATH}/cache_builder
COPY --from=kubectx ${BIN_PATH}/kubectx ${K8S_PATH}/kubectx
COPY --from=kubectx ${BIN_PATH}/kubens ${K8S_PATH}/kubens
COPY --from=kubeval ${BIN_PATH}/kubeval ${K8S_PATH}/kubeval
COPY --from=kustomize ${BIN_PATH}/kustomize ${K8S_PATH}/kustomize
COPY --from=linkerd ${BIN_PATH}/linkerd ${K8S_PATH}/linkerd
COPY --from=octant ${BIN_PATH}/octant ${K8S_PATH}/octant
COPY --from=skaffold ${BIN_PATH}/skaffold ${K8S_PATH}/skaffold
COPY --from=stern ${BIN_PATH}/stern ${K8S_PATH}/stern
COPY --from=telepresence ${BIN_PATH}/telepresence ${K8S_PATH}/telepresence
