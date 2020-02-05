FROM kpango/dev-base:latest AS kube-base

ENV ARCH amd64
ENV OS linux
ENV BIN_PATH /usr/local/bin
ENV TELEPRESENCE_VERSION 0.104

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    apk update \
    && apk upgrade \
    && apk --update add --no-cache --allow-untrusted --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    make \
    curl \
    gcc \
    py3-pip \
    python3-dev \
    openssl \
    bash \
    git \
    upx \
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
    && git clone "https://github.com/ahmetb/kubectx" /opt/kubectx \
    && mv /opt/kubectx/kubectx ${BIN_PATH}/kubectx \
    && mv /opt/kubectx/kubens ${BIN_PATH}/kubens

FROM kube-base AS krew
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/$(curl --silent https://github.com/kubernetes-sigs/krew/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/krew.{tar.gz,yaml}" \
    && tar zxvf krew.tar.gz \
    && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_${ARCH}" install --manifest=krew.yaml --archive=krew.tar.gz

FROM kube-base AS kubebox
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSL "https://github.com/astefanutti/kubebox/releases/download/$(curl --silent https://github.com/astefanutti/kubebox/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/kubebox-${OS}" -o ${BIN_PATH}/kubebox \
    && chmod a+x ${BIN_PATH}/kubebox

FROM kube-base AS stern
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSL "https://github.com/wercker/stern/releases/download/$(curl --silent https://github.com/wercker/stern/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/stern_${OS}_${ARCH}" -o ${BIN_PATH}/stern \
    && chmod a+x ${BIN_PATH}/stern

FROM kube-base AS kubebuilder
RUN set -x; cd "$(mktemp -d)" \
    && KUBEBUILDER_VERSION="$(curl --silent https://github.com/kubernetes-sigs/kubebuilder/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "https://github.com/kubernetes-sigs/kubebuilder/releases/download/v${KUBEBUILDER_VERSION}/kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz \
    && mv kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}/bin/* ${BIN_PATH}/

FROM kube-base AS kind
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/$(curl --silent https://github.com/kubernetes-sigs/kind/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/kind-${OS}-${ARCH}" -o ${BIN_PATH}/kind \
    && chmod a+x ${BIN_PATH}/kind

FROM kube-base AS kubectl-fzf
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "https://github.com/bonnefoa/kubectl-fzf/releases/download/$(curl --silent https://github.com/bonnefoa/kubectl-fzf/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#')/kubectl-fzf_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubectl-fzf_${OS}_${ARCH}.tar.gz \
    && mv cache_builder ${BIN_PATH}/cache_builder

FROM kube-base AS k9s
RUN set -x; cd "$(mktemp -d)" \
    && K9S_VERSION="$(curl --silent https://github.com/derailed/k9s/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -fsSLO "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_${K9S_VERSION}_Linux_x86_64.tar.gz" \
    && tar -zxvf k9s_${K9S_VERSION}_Linux_x86_64.tar.gz \
    && mv k9s ${BIN_PATH}/k9s

FROM kube-base AS telepresence
RUN set -x; cd "$(mktemp -d)" \
    && curl -fsSLO "https://github.com/telepresenceio/telepresence/archive/${TELEPRESENCE_VERSION}.tar.gz" \
    && tar -zxvf ${TELEPRESENCE_VERSION}.tar.gz \
    && env PREFIX=/usr/local telepresence-${TELEPRESENCE_VERSION}/install.sh

FROM kube-base AS linkerd
RUN set -x; cd "$(mktemp -d)" \
    && curl -sL https://run.linkerd.io/install | sh \
    && mv ${HOME}/.linkerd2/bin/linkerd-* ${BIN_PATH}/linkerd

FROM kpango/dev-base:latest AS kube

COPY --from=helm /usr/local/bin/helm /usr/local/bin/helm
COPY --from=k9s /usr/local/bin/k9s /usr/local/bin/k9s
COPY --from=kind /usr/local/bin/kind /usr/local/bin/kind
COPY --from=krew /root/.krew/bin/kubectl-krew /usr/local/bin/kubectl-krew
COPY --from=kubebox /usr/local/bin/kubebox /usr/local/bin/kubebox
COPY --from=kubebuilder /usr/local/bin/kubebuilder /usr/local/bin/kubebuilder
COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=kubectl-fzf /usr/local/bin/cache_builder /usr/local/bin/cache_builder
COPY --from=kubectx /usr/local/bin/kubectx /usr/local/bin/kubectx
COPY --from=kubectx /usr/local/bin/kubens /usr/local/bin/kubens
COPY --from=linkerd /usr/local/bin/linkerd /usr/local/bin/linkerd
COPY --from=stern /usr/local/bin/stern /usr/local/bin/stern
COPY --from=telepresence /usr/local/bin/telepresence /usr/local/bin/telepresence
