FROM kpango/dev-base:latest AS kube-base

ENV ARCH amd64
ENV OS linux
ENV GITHUB https://github.com
ENV RELEASE_DL release/download
ENV RELEASE_LATEST release/download
ENV LOCAL /usr/local
ENV BIN_PATH ${LOCAL}/bin
ENV TELEPRESENCE_VERSION 0.104

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.8 \
    python3-setuptools \
    python3-pip \
    python3-venv \
    && mkdir -p ${BIN_PATH}

FROM kube-base AS kubectl
RUN set -x; cd "$(mktemp -d)" \
    && mkdir -p ${BIN_PATH} \
    && curl -fsSL "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/${OS}/${ARCH}/kubectl" -o ${BIN_PATH}/kubectl \
    && chmod a+x ${BIN_PATH}/kubectl \
    && ${BIN_PATH}/kubectl version --client

FROM kube-base AS helm
RUN set -x; cd "$(mktemp -d)" \
    && curl "https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3" | bash

FROM kube-base AS kubectx
RUN set -x; cd "$(mktemp -d)" \
    && git clone "${GITHUB}/ahmetb/kubectx" /opt/kubectx \
    && mv /opt/kubectx/kubectx ${BIN_PATH}/kubectx \
    && mv /opt/kubectx/kubens ${BIN_PATH}/kubens

FROM kube-base AS krew
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "${GITHUB}/kubernetes-sigs/krew/releases/download/$(curl --silent ${GITHUB}/kubernetes-sigs/krew/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/krew.{tar.gz,yaml}" \
    && tar zxvf krew.tar.gz \
    && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_${ARCH}" install --manifest=krew.yaml --archive=krew.tar.gz

FROM kube-base AS kubebox
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSL "${GITHUB}/astefanutti/kubebox/releases/download/$(curl --silent ${GITHUB}/astefanutti/kubebox/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/kubebox-${OS}" -o ${BIN_PATH}/kubebox \
    && chmod a+x ${BIN_PATH}/kubebox

FROM kube-base AS stern
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSL "${GITHUB}/wercker/stern/releases/download/$(curl --silent ${GITHUB}/wercker/stern/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/stern_${OS}_${ARCH}" -o ${BIN_PATH}/stern \
    && chmod a+x ${BIN_PATH}/stern

FROM kube-base AS kubebuilder
RUN set -x; cd "$(mktemp -d)" \
    && KUBEBUILDER_VERSION="$(curl --silent ${GITHUB}/kubernetes-sigs/kubebuilder/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/kubernetes-sigs/kubebuilder/releases/download/v${KUBEBUILDER_VERSION}/kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz \
    && mv kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}/bin/* ${BIN_PATH}/

FROM kube-base AS kind
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSL "${GITHUB}/kubernetes-sigs/kind/releases/download/$(curl --silent ${GITHUB}/kubernetes-sigs/kind/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/kind-${OS}-${ARCH}" -o ${BIN_PATH}/kind \
    && chmod a+x ${BIN_PATH}/kind

FROM kube-base AS kubectl-fzf
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "${GITHUB}/bonnefoa/kubectl-fzf/releases/download/$(curl --silent ${GITHUB}/bonnefoa/kubectl-fzf/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/kubectl-fzf_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubectl-fzf_${OS}_${ARCH}.tar.gz \
    && mv cache_builder ${BIN_PATH}/cache_builder

FROM kube-base AS k9s
RUN set -x; cd "$(mktemp -d)" \
    && K9S_VERSION="$(curl --silent ${GITHUB}/derailed/k9s/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_x86_64.tar.gz" \
    && tar -zxvf k9s_Linux_x86_64.tar.gz \
    && mv k9s ${BIN_PATH}/k9s

FROM kube-base AS telepresence
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "${GITHUB}/telepresenceio/telepresence/archive/${TELEPRESENCE_VERSION}.tar.gz" \
    && tar -zxvf ${TELEPRESENCE_VERSION}.tar.gz \
    && env PREFIX=${LOCAL} telepresence-${TELEPRESENCE_VERSION}/install.sh

FROM kube-base AS kube-profefe
RUN set -x; cd "$(mktemp -d)" \
    && KUBE_PROFEFE_VERSION="$(curl --silent ${GITHUB}/profefe/kube-profefe/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "${GITHUB}/profefe/kube-profefe/releases/download/v${KUBE_PROFEFE_VERSION}/kube-profefe_${KUBE_PROFEFE_VERSION}_Linux_x86_64.tar.gz" \
    && tar -zxvf "kube-profefe_${KUBE_PROFEFE_VERSION}_Linux_x86_64.tar.gz" \
    && mv kprofefe ${BIN_PATH}/kprofefe \
    && mv kubectl-profefe ${BIN_PATH}/kubectl-profefe

FROM kube-base AS kube-tree
RUN set -x; cd "$(mktemp -d)" \
    && KUBETREE_VERSION="$(curl --silent ${GITHUB}/ahmetb/kubectl-tree/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO ${GITHUB}/ahmetb/kubectl-tree/releases/download/v${KUBETREE_VERSION}/kubectl-tree_v${KUBETREE_VERSION}_linux_amd64.tar.gz \
    && tar -zxvf "kubectl-tree_v${KUBETREE_VERSION}_linux_amd64.tar.gz" \
    && mv kubectl-tree ${BIN_PATH}/kubectl-tree

FROM kube-base AS linkerd
RUN set -x; cd "$(mktemp -d)" \
    && curl -sL https://run.linkerd.io/install | sh \
    && mv ${HOME}/.linkerd2/bin/linkerd-* ${BIN_PATH}/linkerd


FROM kube-base AS octant
RUN set -x; cd "$(mktemp -d)" \
    && OCTANT_VERSION="$(curl --silent ${GITHUB}/vmware-tanzu/octant/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO ${GITHUB}/vmware-tanzu/octant/releases/download/v${OCTANT_VERSION}/octant_${OCTANT_VERSION}_Linux-64bit.tar.gz \
    && tar -zxvf "octant_${OCTANT_VERSION}_Linux-64bit.tar.gz" \
    && mv octant_${OCTANT_VERSION}_Linux-64bit/octant ${BIN_PATH}/octant

FROM kube-base AS skaffold
RUN set -x; cd "$(mktemp -d)" \
    && SKAFFOLD_VERSION="$(curl --silent ${GITHUB}/GoogleContainerTools/skaffold/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/v${SKAFFOLD_VERSION}/skaffold-linux-amd64 \
    && chmod +x skaffold \
    && mv skaffold ${BIN_PATH}/skaffold

FROM kpango/dev-base:latest AS kube

ENV BIN_PATH /usr/local/bin
COPY --from=helm ${BIN_PATH}/helm ${BIN_PATH}/helm
COPY --from=k9s ${BIN_PATH}/k9s ${BIN_PATH}/k9s
COPY --from=kind ${BIN_PATH}/kind ${BIN_PATH}/kind
COPY --from=krew /root/.krew/bin/kubectl-krew ${BIN_PATH}/kubectl-krew
COPY --from=kube-profefe ${BIN_PATH}/kprofefe ${BIN_PATH}/kprofefe
COPY --from=kube-profefe ${BIN_PATH}/kubectl-profefe ${BIN_PATH}/kubectl-profefe
COPY --from=kube-tree ${BIN_PATH}/kubectl-tree ${BIN_PATH}/kubectl-tree
COPY --from=kubebox ${BIN_PATH}/kubebox ${BIN_PATH}/kubebox
COPY --from=kubebuilder ${BIN_PATH}/kubebuilder ${BIN_PATH}/kubebuilder
COPY --from=kubectl ${BIN_PATH}/kubectl ${BIN_PATH}/kubectl
COPY --from=kubectl-fzf ${BIN_PATH}/cache_builder ${BIN_PATH}/cache_builder
COPY --from=kubectx ${BIN_PATH}/kubectx ${BIN_PATH}/kubectx
COPY --from=kubectx ${BIN_PATH}/kubens ${BIN_PATH}/kubens
COPY --from=linkerd ${BIN_PATH}/linkerd ${BIN_PATH}/linkerd
COPY --from=octant ${BIN_PATH}/octant ${BIN_PATH}/octant
COPY --from=stern ${BIN_PATH}/stern ${BIN_PATH}/stern
COPY --from=skaffold ${BIN_PATH}/skaffold ${BIN_PATH}/skaffold
COPY --from=telepresence ${BIN_PATH}/telepresence ${BIN_PATH}/telepresence
