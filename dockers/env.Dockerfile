# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS env-base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG GROUP_IDS=${GROUP_ID}

ENV LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib \
    BASE_DIR=/home \
    USER=${WHOAMI} \
    SHELL=/usr/bin/zsh \
    GROUP=sudo,root,users,docker,wheel
ENV HOME=${BASE_DIR}/${USER}

RUN groupadd --non-unique --gid ${GROUP_ID} docker \
    && groupadd --non-unique --gid ${GROUP_ID} wheel \
    && groupmod --non-unique --gid ${GROUP_ID} users \
    && useradd --uid ${USER_ID} \
        --gid ${GROUP_ID} \
        --non-unique --create-home \
        --shell ${SHELL} \
        --base-dir ${BASE_DIR} \
        --home ${HOME} \
        --groups ${GROUP} ${USER} \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && sed -i -e 's/# %users\tALL=(ALL)\tNOPASSWD: ALL/%users\tALL=(ALL)\tNOPASSWD: ALL/' /etc/sudoers \
    && sed -i -e 's/%users\tALL=(ALL)\tALL/# %users\tALL=(ALL)\tALL/' /etc/sudoers \
    && chown -R 0:0 /etc/sudoers.d \
    && chown -R 0:0 /etc/sudoers \
    && chmod -R 0440 /etc/sudoers.d \
    && chmod -R 0440 /etc/sudoers \
    && visudo -c

WORKDIR /tmp
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=cache,id=bun-cache-${TARGETARCH},target=${HOME}/.bun/install/cache,sharing=locked \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=secret,id=gat \
    printf '%s\n' \
        /lib \
        /lib64 \
        /var/lib \
        /usr/lib \
        /usr/local/lib \
        /usr/local/go/lib \
        /usr/local/clang/lib \
        /usr/lib/dart/lib \
        /usr/lib/node_modules/lib \
        /google-cloud-sdk/lib \
        > /etc/ld.so.conf.d/usr-local-lib.conf \
    && ldconfig \
    && git clone --depth 1 ${GITHUB}/soimort/translate-shell /tmp/translate-shell \
    && make TARGET=zsh -j -C /tmp/translate-shell \
    && make install -C /tmp/translate-shell \
    && chown -R ${USER}:users ${HOME} \
    && chmod -R 755 ${HOME} \
    && make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=bun REPO=oven-sh/bun EXT=.zip \
        BIN_SUBDIR='bun-$(OS)-$(if $(filter amd64,$(ARCH)),x64-baseline,aarch64)' \
        URL_TEMPLATE='$(GITHUB)/oven-sh/bun/$(RELEASE_DL)/$(VERSION)/bun-$(OS)-$(if $(filter amd64,$(ARCH)),x64-baseline,aarch64).zip' \
    && chmod a+x "${LOCAL}/bin/bun"

FROM env-base AS env
WORKDIR ${HOME}
