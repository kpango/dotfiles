# syntax = docker/dockerfile:latest
FROM --platform=$BUILDPLATFORM kpango/base:latest AS env-base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV AARCH aarch_64
ENV XARCH x86_64
ENV GITHUBCOM github.com
ENV GITHUB https://${GITHUBCOM}
ENV API_GITHUB https://api.${GITHUBCOM}/repos
ENV RAWGITHUB https://raw.githubusercontent.com
ENV GOOGLE https://storage.googleapis.com
ENV RELEASE_DL releases/download
ENV RELEASE_LATEST releases/latest
ENV LOCAL /usr/local
ENV BIN_PATH ${LOCAL}/bin

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG GROUP_IDS=${GROUP_ID}
ARG WHOAMI=kpango

ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib
ENV BASE_DIR /home
ENV USER ${WHOAMI}
ENV HOME ${BASE_DIR}/${USER}
ENV SHELL /usr/bin/zsh
ENV GROUP sudo,root,users,docker,wheel
ENV UID ${USER_ID}

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
RUN --mount=type=cache,target=${HOME}/.npm \
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
    && echo $(ldconfig) \
    && apt update -y \
    && apt upgrade -y \
    && apt install -y --no-install-recommends --fix-missing \
    automake \
    bash \
    ccls \
    clang-format \
    clangd \
    diffutils \
    exuberant-ctags \
    gawk \
    gettext \
    graphviz \
    jq \
    less \
    libhdf5-serial-dev \
    liblapack-dev \
    libncurses5-dev \
    libomp-dev \
    libopenblas-dev \
    libtool \
    libtool-bin \
    luajit \
    mariadb-client \
    mtr \
    ncurses-term \
    nodejs \
    npm \
    openssh-client \
    pass \
    perl \
    pkg-config \
    python3-dev \
    python3-pip \
    python3-setuptools \
    ruby-dev \
    sass \
    sed \
    tar \
    tig \
    tmux \
    ugrep \
    xclip \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 https://github.com/neovim/neovim \
    && cd neovim \
    && rm -rf build \
    && make CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX:PATH=/usr" CMAKE_BUILD_TYPE=Release \
    && make install \
    && cd /tmp && rm -rf /tmp/neovim \
    && pip3 install --upgrade --break-system-packages pip neovim ranger-fm thefuck httpie python-language-server vim-vint grpcio-tools \
    && gem install neovim -N \
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
    && npm install -g n

FROM --platform=$BUILDPLATFORM env-base AS env-stage
WORKDIR /tmp
RUN --mount=type=cache,target=${HOME}/.npm \
    n latest \
    && bash -c "chown -R ${USER} $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && bash -c "chmod -R 755 $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && npm install -g \
        yarn \
    && yarn global add \
        diagnostic-languageserver \
        dockerfile-language-server-nodejs \
        bash-language-server \
        markdownlint-cli \
        neovim \
        npm \
        typescript \
        typescript-language-server \
        terminalizer \
        prettier \
    && bash -c "chown -R ${USER} $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && bash -c "chmod -R 755 $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && apt purge -y nodejs npm \
    && apt -y autoremove

FROM --platform=$BUILDPLATFORM env-base AS protoc
WORKDIR /tmp
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && REPO_NAME="protobuf" \
    && BIN_NAME="protoc" \
    && REPO="protocolbuffers/${REPO_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
    && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && unset HEADER \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && if [ "${ARCH}" = "arm64" ] ; then  ARCH=${AARCH} ; fi \
    && ZIP_NAME="${BIN_NAME}-${VERSION}-${OS}-${ARCH}" \
    && curl -fsSL "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ZIP_NAME}.zip" -o "/tmp/${BIN_NAME}.zip" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local "bin/${BIN_NAME}" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local 'include/*' \
    && rm -f /tmp/protoc.zip \
    && rm -rf /tmp/*

FROM --platform=$BUILDPLATFORM env-base AS ngt
WORKDIR /tmp
ENV NGT_VERSION main
ENV CFLAGS "-mno-avx512f -mno-avx512dq -mno-avx512cd -mno-avx512bw -mno-avx512vl"
ENV CXXFLAGS ${CFLAGS}
ENV LDFLAGS="-L/etc/altenatives ${LDFLAGS}"
RUN echo $(ldconfig) \
    && echo ${LDFLAGS} \
    && rm -rf /tmp/* /var/cache \
    && git clone -b ${NGT_VERSION} --depth 1 https://github.com/yahoojapan/NGT "/tmp/NGT-${NGT_VERSION}" \
    && cd "/tmp/NGT-${NGT_VERSION}" \
    && if [ "${ARCH}" = "arm64" ] ; then  CFLAGS="" && CXXFLAGS="" ; fi \
    && CC=$(which gcc) CXX=$(which g++) cmake -DNGT_LARGE_DATASET=ON . \
    && CC=$(which gcc) CXX=$(which g++) make -j -C "/tmp/NGT-${NGT_VERSION}" \
    && CC=$(which gcc) CXX=$(which g++) make install -C "/tmp/NGT-${NGT_VERSION}" \
    && cd /tmp \
    && rm -rf /tmp/*

# FROM --platform=$BUILDPLATFORM env-base AS tensorflow
# WORKDIR /tmp
# RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
#     && REPO_NAME="tensorflow" \
#     && BIN_NAME="${REPO_NAME}" \
#     && REPO="${REPO_NAME}/${BIN_NAME}" \
#     && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
#     && BODY="$(curl --silent -H ${HEADER} ${API_GITHUB}/${REPO}/${RELEASE_LATEST})" \
#     && VERSION=$(echo "${BODY}" | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g') \
#     && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
#     && unset HEADER \
#     && BIN_NAME="lib${REPO_NAME}" \
#     && REPO="${REPO_NAME}/${BIN_NAME}" \
#     && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
#     && URL="${GOOGLE}/${REPO}/${BIN_NAME}-cpu-${OS}-${ARCH}-${VERSION}.tar.gz" \
#     && echo "${URL}" \
#     && curl -fsSLo "/tmp/${BIN_NAME}.tar.gz" "${URL}" \
#     && tar -C /usr/local -xzf "/tmp/${BIN_NAME}.tar.gz" \
#     && rm -rf /tmp/*

FROM --platform=$BUILDPLATFORM env-stage AS env

ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

COPY --from=ngt ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --from=ngt ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --from=ngt ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
# COPY --from=tensorflow ${LOCAL}/include/tensorflow ${LOCAL}/include/tensorflow
# COPY --from=tensorflow ${LOCAL}/lib/libtensorflow* ${LOCAL}/lib/
COPY --from=protoc ${BIN_PATH}/protoc ${BIN_PATH}/protoc
COPY --from=protoc ${LOCAL}/include/google/protobuf ${LOCAL}/include/google/protobuf

RUN ldconfig \
    && rm -rf /tmp/* /var/cache

WORKDIR ${HOME}
