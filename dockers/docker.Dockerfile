FROM kpango/dev-base:latest AS docker-base

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
RUN curl -fsSLO "https://downloads.dockerslim.com/releases/$(curl --silent https://github.com/docker-slim/docker-slim/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#'  | sed 's/v//g')/dist_linux.tar.gz" \
    && tar zxvf dist_linux.tar.gz \
    && mv dist_linux/docker* /usr/local/bin \
    && upx -9 \
        /usr/local/bin/docker-slim \
        /usr/local/bin/docker-slim-sensor

FROM docker-base AS dlayer
RUN curl -fSsLO "https://github.com/orisano/dlayer/releases/download/v$(curl --silent https://github.com/orisano/dlayer/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#'  | sed 's/v//g')/dlayer_0.2.2_Linux_x86_64.tar.gz" \
    && tar zxvf dlayer_0.2.2_Linux_x86_64.tar.gz \
    && mv dlayer /usr/local/bin \
    && upx -9 \
        /usr/local/bin/dlayer

FROM docker-base AS buildx
RUN mkdir -p /usr/lib/docker/cli-plugins \
    && BUILDX_VER="$(curl --silent https://github.com/docker/buildx/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')" \
    && curl -o /usr/lib/docker/cli-plugins/docker-buildx -fSsLO "https://github.com/docker/buildx/releases/download/v${BUILDX_VER}/buildx-v${BUILDX_VER}.linux-amd64" \
    && chmod a+x /usr/lib/docker/cli-plugins/docker-buildx \
    && upx -9 \
        /usr/lib/docker/cli-plugins/docker-buildx

FROM docker-base AS dockfmt
RUN curl -fSL "https://github.com/jessfraz/dockfmt/releases/download/v$(curl --silent https://github.com/jessfraz/dockfmt/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')/dockfmt-linux-amd64" -o "/usr/local/bin/dockfmt" \
	&& chmod a+x "/usr/local/bin/dockfmt" \
    && upx -9 \
        /usr/local/bin/dockfmt

FROM docker-base AS container-diff
RUN curl -LO "https://storage.googleapis.com/container-diff/latest/container-diff-linux-amd64" \
    && chmod a+x container-diff-linux-amd64 \
    && mv container-diff-linux-amd64 /usr/local/bin/container-diff \
    && upx -9 \
        /usr/local/bin/container-diff

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

COPY --from=buildx /usr/lib/docker/cli-plugins/docker-buildx /usr/lib/docker/cli-plugins/docker-buildx
COPY --from=common /usr/local/bin/containerd /usr/bin/docker-containerd
COPY --from=common /usr/local/bin/containerd-shim /usr/bin/docker-containerd-shim
COPY --from=common /usr/local/bin/ctr /usr/bin/docker-containerd-ctr
COPY --from=common /usr/local/bin/dind /usr/bin/dind
COPY --from=common /usr/local/bin/docker /usr/bin/docker
COPY --from=common /usr/local/bin/docker-entrypoint.sh /usr/bin/docker-entrypoint
COPY --from=common /usr/local/bin/docker-init /usr/bin/docker-init
COPY --from=common /usr/local/bin/docker-proxy /usr/bin/docker-proxy
COPY --from=common /usr/local/bin/dockerd /usr/bin/dockerd
COPY --from=common /usr/local/bin/dockerd-entrypoint.sh /usr/bin/dockerd-entrypoint
COPY --from=common /usr/local/bin/modprobe /usr/bin/modprobe
COPY --from=common /usr/local/bin/runc /usr/bin/docker-runc
COPY --from=dive /usr/local/bin/dive /usr/bin/dive
COPY --from=dlayer /usr/local/bin/dlayer /usr/bin/dlayer
COPY --from=dockfmt /usr/local/bin/dockfmt /usr/bin/dockfmt
COPY --from=dockle /usr/local/bin/dockle /usr/bin/dockle
COPY --from=slim /usr/local/bin/docker-slim /usr/bin/docker-slim
COPY --from=slim /usr/local/bin/docker-slim-sensor /usr/bin/docker-slim-sensor
COPY --from=trivy /usr/local/bin/trivy /usr/bin/trivy
COPY --from=container-diff /usr/local/bin/container-diff /usr/bin/container-diff

