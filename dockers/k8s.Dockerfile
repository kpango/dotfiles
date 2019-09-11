FROM alpine:edge AS kube

ENV ARCH amd64
ENV OS linux
ENV KREW_VERSION v0.2.1
ENV KUBEBOX_VERSION v0.4.0
ENV STERN_VERSION 1.10.0
ENV KUBEBUILDER_VERSION 1.0.8

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
    && curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/${OS}/${ARCH}/kubectl" \
    && mv ./kubectl /usr/local/bin/kubectl \
    && chmod a+x /usr/local/bin/kubectl \
    && kubectl version --client \
    && curl "https://raw.githubusercontent.com/helm/helm/master/scripts/get" | bash \
    && git clone "https://github.com/ahmetb/kubectx" /opt/kubectx \
    && mv /opt/kubectx/kubectx /usr/local/bin/kubectx \
    && mv /opt/kubectx/kubens /usr/local/bin/kubens \
    && curl -fsSLO "https://storage.googleapis.com/krew/${KREW_VERSION}/krew.{tar.gz,yaml}" \
    && tar zxvf krew.tar.gz \
    && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_${ARCH}" install --manifest=krew.yaml --archive=krew.tar.gz \
    && ls /root/.krew \
    && ls /root/.krew/bin \
    && curl -Lo kubebox "https://github.com/astefanutti/kubebox/releases/download/${KUBEBOX_VERSION}/kubebox-${OS}" \
    && chmod +x kubebox \
    && mv kubebox /usr/local/bin/kubebox \
    && curl -fsSL "https://github.com/wercker/stern/releases/download/${STERN_VERSION}/stern_${OS}_${ARCH}" -o stern \
    && chmod +x stern \
    && mv stern /usr/local/bin/stern \
    && curl -L -O "https://github.com/kubernetes-sigs/kubebuilder/releases/download/v${KUBEBUILDER_VERSION}/kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz" \
    && tar -zxvf kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}.tar.gz \
    && mv kubebuilder_${KUBEBUILDER_VERSION}_${OS}_${ARCH}/bin/* /usr/local/bin/

# RUN upx --best --ultra-brute \
#         /usr/local/bin/helm \
#         /usr/local/bin/kubectx \
#         /usr/local/bin/kubens \
#         /usr/local/bin/stern \
#         # /root/.krew/bin/* \
#         # /usr/local/bin/kubebox \
#         2> /dev/null
