FROM docker:rc-dind AS docker
RUN apk update \
    && apk upgrade \
    && apk add --no-cache upx \
    && upx --best --ultra-brute \
        /usr/local/bin/containerd \
        /usr/local/bin/containerd-shim \
        /usr/local/bin/ctr \
        /usr/local/bin/docker \
        /usr/local/bin/docker-init \
        /usr/local/bin/docker-proxy \
        /usr/local/bin/dockerd \
        /usr/local/bin/runc

