FROM kpango/dev-base:latest AS docker-base
ENV DOCKER_SLIM_VERSION 1.26.1
ENV DLAYER_VERSION 0.1.0
ENV BUILDX_VER 0.3.1

FROM aquasec/trivy:latest AS trivy

FROM goodwithtech/dockle:latest AS dockle-base
FROM docker-base AS dockle
COPY --from=dockle-base /usr/local/bin/dockle /usr/local/bin/dockle
RUN upx -9 \
        /usr/local/bin/dockle

FROM wagoodman/dive:latest AS dive-base
FROM docker-base AS dive
COPY --from=dive-base /usr/local/bin/dive /usr/local/bin/dive
RUN upx -9 \
        /usr/local/bin/dive

FROM docker-base AS slim
RUN curl -fsSLO "https://downloads.dockerslim.com/releases/${DOCKER_SLIM_VERSION}/dist_linux.tar.gz" \
    && tar zxvf dist_linux.tar.gz \
    && mv dist_linux/docker* /usr/local/bin \
    && upx -9 \
        /usr/local/bin/docker-slim \
        /usr/local/bin/docker-slim-sensor

FROM docker-base AS dlayer
RUN curl -o /usr/local/bin/dlayer -fSsLO "https://github.com/orisano/dlayer/releases/download/v${DLAYER_VERSION}/dlayer_linux_amd64" \
    && chmod a+x /usr/local/bin/dlayer \
    && upx -9 \
        /usr/local/bin/dlayer

FROM docker-base AS buildx
RUN mkdir -p /usr/lib/docker/cli-plugins \
    && curl -o /usr/lib/docker/cli-plugins/docker-buildx -fSsLO "https://github.com/docker/buildx/releases/download/v${BUILDX_VER}/buildx-v${BUILDX_VER}.linux-amd64" \
    && chmod a+x /usr/lib/docker/cli-plugins/docker-buildx \
    && upx -9 \
        /usr/lib/docker/cli-plugins/docker-buildx

FROM docker:rc-dind AS common
RUN apk upgrade \
    && apk add --no-cache \
    upx \
    && upx -9 \
        /usr/local/bin/containerd \
        /usr/local/bin/containerd-shim \
        /usr/local/bin/ctr \
        /usr/local/bin/docker \
        /usr/local/bin/docker-init \
        /usr/local/bin/docker-proxy \
        /usr/local/bin/dockerd \
        /usr/local/bin/runc

FROM scratch AS docker

COPY --from=dive /usr/local/bin/dive /usr/bin/dive
COPY --from=dockle /usr/local/bin/dockle /usr/bin/dockle
COPY --from=trivy /usr/local/bin/trivy /usr/bin/trivy
COPY --from=buildx /usr/lib/docker/cli-plugins/docker-buildx /usr/lib/docker/cli-plugins/docker-buildx
COPY --from=slim /usr/local/bin/docker-slim /usr/bin/docker-slim
COPY --from=slim /usr/local/bin/docker-slim-sensor /usr/bin/docker-slim-sensor
COPY --from=dlayer /usr/local/bin/dlayer /usr/bin/dlayer
COPY --from=common /usr/local/bin/containerd /usr/bin/docker-containerd
COPY --from=common /usr/local/bin/containerd-shim /usr/bin/docker-containerd-shim
COPY --from=common /usr/local/bin/ctr /usr/bin/docker-containerd-ctr
COPY --from=common /usr/local/bin/dind /usr/bin/dind
COPY --from=common /usr/local/bin/docker /usr/bin/docker
COPY --from=common /usr/local/bin/docker-entrypoint.sh /usr/bin/docker-entrypoint
COPY --from=common /usr/local/bin/dockerd-entrypoint.sh /usr/bin/dockerd-entrypoint
COPY --from=common /usr/local/bin/docker-init /usr/bin/docker-init
COPY --from=common /usr/local/bin/docker-proxy /usr/bin/docker-proxy
COPY --from=common /usr/local/bin/dockerd /usr/bin/dockerd
COPY --from=common /usr/local/bin/modprobe /usr/bin/modprobe
COPY --from=common /usr/local/bin/runc /usr/bin/docker-runc

