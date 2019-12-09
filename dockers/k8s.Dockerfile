FROM alpine:edge AS kube

ENV ARCH amd64
ENV OS linux
ENV BIN_PATH /usr/local/bin
ENV KREW_VERSION v0.3.1
ENV KUBEBOX_VERSION v0.6.1
ENV STERN_VERSION 1.11.0
ENV KUBEBUILDER_VERSION 2.0.1
ENV KIND_VERSION 0.5.1

RUN apk update \
    && apk upgrade \
    && apk --update add --no-cache \
    make \
    curl \
    gcc \
    openssl \
    bash \
    git \
    upx

RUN set -x; cd "$(mktemp -d)" \
    && mkdir -p ${BIN_PATH} \
    && curl -fsSL "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/${OS}/${ARCH}/kubectl" -o ${BIN_PATH}/kubectl \
    && chmod a+x ${BIN_PATH}/kubectl \
    && ${BIN_PATH}/kubectl version --client \
    && curl "https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3" | bash \
    && git clone "https://github.com/ahmetb/kubectx" /opt/kubectx \
    && mv /opt/kubectx/kubectx ${BIN_PATH}/kubectx \
    && mv /opt/kubectx/kubens ${BIN_PATH}/kubens \
    && curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/krew.{tar.gz,yaml}" \
    && tar zxvf krew.tar.gz \
    && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_${ARCH}" install --manifest=krew.yaml --archive=krew.tar.gz \
    && ls /root/.krew \
    && ls /root/.krew/bin \
    && curl -fsSL "https://github.com/astefanutti/kubebox/releases/download/${KUBEBOX_VERSION}/kubebox-${OS}" -o ${BIN_PATH}/kubebox \
    && chmod a+x ${BIN_PATH}/kubebox \
    && curl -fsSL "https://github.com/wercker/stern/releases/download/${STERN_VERSION}/stern_${OS}_${ARCH}" -o ${BIN_PATH}/stern \
    && chmod a+x ${BIN_PATH}/stern \
    && curl -fsSLO "https://github.com/kubernetes-sigs/kubebuilder/releases/download/v${KUBEBUILDER_VERSION}/kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz \
    && mv kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}/bin/* ${BIN_PATH}/ \
    && curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-${OS}-${ARCH}" -o ${BIN_PATH}/kind \
    && chmod a+x ${BIN_PATH}/kind \
    && curl -sL https://run.linkerd.io/install | sh \
    && mv ${HOME}/.linkerd2/bin/linkerd-* ${BIN_PATH}/linkerd

# RUN upx --best --ultra-brute \
#         ${BIN_PATH}/helm \
#         ${BIN_PATH}/kubectx \
#         ${BIN_PATH}/kubens \
#         ${BIN_PATH}/stern \
#         # /root/.krew/bin/* \
#         # ${BIN_PATH}/kubebox \
#         2> /dev/null
