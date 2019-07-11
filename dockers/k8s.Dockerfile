FROM alpine:edge AS kube

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
    && curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" \
    && mv ./kubectl /usr/local/bin/kubectl \
    && chmod a+x /usr/local/bin/kubectl \
    && kubectl version --client \
    && curl "https://raw.githubusercontent.com/helm/helm/master/scripts/get" | bash \
    && git clone "https://github.com/ahmetb/kubectx" /opt/kubectx \
    && mv /opt/kubectx/kubectx /usr/local/bin/kubectx \
    && mv /opt/kubectx/kubens /usr/local/bin/kubens \
    && curl -fsSLO "https://storage.googleapis.com/krew/v0.2.1/krew.{tar.gz,yaml}" \
    && tar zxvf krew.tar.gz \
    && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" install --manifest=krew.yaml --archive=krew.tar.gz \
    && ls /root/.krew \
    && ls /root/.krew/bin \
    && curl -Lo kubebox https://github.com/astefanutti/kubebox/releases/download/v0.4.0/kubebox-linux \
    && chmod +x kubebox \
    && mv kubebox /usr/local/bin/kubebox \
    && curl -fsSL "https://github.com/wercker/stern/releases/download/1.10.0/stern_linux_amd64" -o stern \
    && chmod +x stern \
    && mv stern /usr/local/bin/stern \
    && version=1.0.8 \
    && arch=amd64 \
    && curl -L -O "https://github.com/kubernetes-sigs/kubebuilder/releases/download/v${version}/kubebuilder_${version}_darwin_${arch}.tar.gz" \
    && tar -zxvf kubebuilder_${version}_darwin_${arch}.tar.gz \
    && mv kubebuilder_${version}_darwin_${arch}/bin/* /usr/local/bin/ \
    && upx --best --ultra-brute \
        /usr/local/bin/helm \
        /usr/local/bin/kubectx \
        /usr/local/bin/kubens \
        /usr/local/bin/stern \
        # /root/.krew/bin/* \
        # /usr/local/bin/kubebox \
        2> /dev/null

