# syntax = docker/dockerfile:latest
FROM kpango/base:latest AS env-base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV AARCH=aarch_64
ENV XARCH=x86_64
ENV GITHUBCOM=github.com
ENV GITHUB=https://${GITHUBCOM}
ENV API_GITHUB=https://api.${GITHUBCOM}/repos
ENV RAWGITHUB=https://raw.githubusercontent.com
ENV GOOGLE=https://storage.googleapis.com
ENV RELEASE_DL=releases/download
ENV RELEASE_LATEST=releases/latest
ENV LOCAL=/usr/local
ENV BIN_PATH=${LOCAL}/bin

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG GROUP_IDS=${GROUP_ID}

ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib
ENV BASE_DIR=/home
ENV USER=${WHOAMI}
ENV HOME=${BASE_DIR}/${USER}
ENV SHELL=/usr/bin/zsh
ENV GROUP=sudo,root,users,docker,wheel
ENV UID=${USER_ID}

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
RUN --mount=type=cache,target=${HOME}/.bun \
    echo '/lib\n\
/lib64\n\
/var/lib\n\
/usr/lib\n\
/usr/local/lib\n\
/usr/local/go/lib\n\
/usr/local/clang/lib\n\
/usr/lib/dart/lib\n\
/usr/lib/node_modules/lib\n\
/google-cloud-sdk/lib' > /etc/ld.so.conf.d/usr-local-lib.conf \
    && ldconfig \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/no-install-recommends \
    && apt-get clean \
    && apt-get update -y \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends --fix-missing \
    automake \
    bash \
    build-essential \
    ca-certificates \
    ccls \
    clang-format \
    clang-tidy \
    clangd \
    cmake \
    curl \
    diffutils \
    exuberant-ctags \
    g++ \
    gawk \
    gcc \
    gettext \
    gfortran \
    git \
    gnupg \
    gnupg2 \
    graphviz \
    jq \
    less \
    libaec-dev \
    libfp16-dev \
    libhdf5-dev \
    libhdf5-serial-dev \
    liblapack-dev \
    libncurses5-dev \
    libomp-dev \
    libopenblas-dev \
    libssl-dev \
    libtool \
    libtool-bin \
    locales \
    lua5.4 \
    luajit \
    luarocks \
    mariadb-client \
    mtr \
    ncurses-term \
    nkf \
    nodejs \
    openssh-client \
    pass \
    perl \
    pinentry-tty \
    pkg-config \
    python3-dev \
    python3-pip \
    python3-setuptools \
    ruby-dev \
    sass \
    sed \
    software-properties-common \
    tar \
    tig \
    tmux \
    tzdata \
    ugrep \
    unzip \
    xclip \
    zip \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 https://github.com/soimort/translate-shell \
    && cd /tmp/translate-shell/ \
    && make TARGET=zsh -j -C /tmp/translate-shell \
    && make install -C /tmp/translate-shell \
    && cd /tmp \
    && rm -rf /tmp/translate-shell/ \
    && apt -y autoremove \
    && chown -R ${USER}:users ${HOME} \
    && chown -R ${USER}:users ${HOME}/.* \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && export BUN_INSTALL=${LOCAL} && curl -fsSL https://bun.sh/install | bash
    # && curl -fsSL https://tailscale.com/install.sh | sh \

FROM env-base AS env-stage
WORKDIR /tmp
ENV PATH=${LOCAL}/bin:${PATH}
ENV BUN_INSTALL=/usr/local/bun
RUN BUN_INSTALL=${BUN_INSTALL} bun install -g \
        prettier \
        markdownlint-cli \
        dockerfile-language-server-nodejs \
        bash-language-server \
        typescript \
        typescript-language-server \
        n \
        @openai/codex \
        @google/gemini-cli \
        @anthropic-ai/claude-code \
        @qwen-code/qwen-code \
    && ${BUN_INSTALL}/bin/n latest

USER root
FROM env-base AS protoc
WORKDIR /tmp
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && REPO_NAME="protobuf" \
    && BIN_NAME="protoc" \
    && REPO="protocolbuffers/${REPO_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && unset HEADER \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && if [ -z "${VERSION}" ]; then \
         echo "Warning: VERSION is empty with auth. ${BODY}. Trying without auth..."; \
         BODY="$(curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST})"; \
         VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g'); \
       fi \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && if [ "${ARCH}" = "arm64" ] ; then  ARCH=${AARCH} ; fi \
    && ZIP_NAME="${BIN_NAME}-${VERSION}-${OS}-${ARCH}" \
    && curl -fsSLo "/tmp/${BIN_NAME}.zip" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ZIP_NAME}.zip" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local "bin/${BIN_NAME}" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local 'include/*' \
    && rm -f /tmp/protoc.zip \
    && rm -rf /tmp/*

FROM env-base AS cmake-base
WORKDIR /tmp
RUN git clone --depth 1 https://github.com/vdaas/vald "/tmp/vald" \
    && cd "/tmp/vald" \
    && make cmake/install

FROM cmake-base AS ngt
WORKDIR /tmp/vald
RUN make ngt/install

FROM cmake-base AS faiss
WORKDIR /tmp/vald
RUN make faiss/install

FROM cmake-base AS usearch
WORKDIR /tmp/vald
RUN make usearch/install

FROM env-stage AS env

ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

COPY --from=ngt ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --from=ngt ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --from=ngt ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
COPY --from=faiss ${LOCAL}/include/faiss ${LOCAL}/include/faiss
COPY --from=faiss ${LOCAL}/lib/libfaiss.* ${LOCAL}/lib/
COPY --from=usearch ${LOCAL}/include/usearch.h ${LOCAL}/include/usearch.h
COPY --from=usearch ${LOCAL}/lib/libusearch* ${LOCAL}/lib/
COPY --from=protoc ${BIN_PATH}/protoc ${BIN_PATH}/protoc
COPY --from=protoc ${LOCAL}/include/google/protobuf ${LOCAL}/include/google/protobuf

RUN ldconfig \
    && rm -rf /tmp/* /var/cache

WORKDIR ${HOME}
