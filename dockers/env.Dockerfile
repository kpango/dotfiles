FROM --platform=$BUILDPLATFORM kpango/dev-base:latest AS env-base

ARG TARGETOS
ARG TARGETARCH

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
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

LABEL maintainer="kpango <kpango@vdaas.org>"

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
RUN echo '/lib\n\
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
    # ugrep \
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
    libncurses5-dev \
    libomp-dev \
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
    xclip \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 https://github.com/neovim/neovim \
    && cd neovim \
    && rm -rf build \
    && make CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX:PATH=/usr" CMAKE_BUILD_TYPE=Release \
    && make install \
    && cd /tmp && rm -rf /tmp/neovim \
    && pip3 install --upgrade pip neovim ranger-fm thefuck httpie python-language-server vim-vint grpcio-tools \
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

RUN n latest \
    && npm config set user ${USER} \
    && bash -c "chown -R ${USER} $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && bash -c "chmod -R 755 $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && npm config set user ${USER} \
    && npm install -g \
        diagnostic-languageserver \
        dockerfile-language-server-nodejs \
        bash-language-server \
        markdownlint-cli \
        neovim \
        npm \
        prettier \
        resume-cli \
        terminalizer \
        typescript \
        typescript-language-server \
        yarn \
    && bash -c "chown -R ${USER} $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && bash -c "chmod -R 755 $(npm config get prefix)/{lib/node_modules,bin,share}" \
    && apt purge -y nodejs npm \
    && apt -y autoremove


FROM env-base AS protoc
WORKDIR /tmp
RUN set -x; cd "$(mktemp -d)" \
    && REPO_NAME="protobuf" \
    && BIN_NAME="protoc" \
    && REPO="protocolbuffers/${REPO_NAME}" \
    && VERSION="$(curl --silent ${API_GITHUB}/${REPO}/${RELEASE_LATEST} | grep -Po '"tag_name": "\K.*?(?=")' | sed 's/v//g')" \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && ZIP_NAME="${BIN_NAME}-${VERSION}-${OS}-${ARCH}" \
    && curl -fsSL "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ZIP_NAME}.zip" -o "/tmp/${BIN_NAME}.zip" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local "bin/${BIN_NAME}" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local 'include/*' \
    && rm -f /tmp/protoc.zip \
    && rm -rf /tmp/*

FROM env-base AS ngt
WORKDIR /tmp
ENV NGT_VERSION 1.14.6
ENV CFLAGS "-mno-avx512f -mno-avx512dq -mno-avx512cd -mno-avx512bw -mno-avx512vl"
ENV CXXFLAGS ${CFLAGS}
# ENV LDFLAGS="-L/usr/local/opt/llvm/lib"
# ENV CPPFLAGS="-I/usr/local/opt/llvm/include"
RUN curl -LO "https://github.com/yahoojapan/NGT/archive/v${NGT_VERSION}.tar.gz" \
    && tar zxf "v${NGT_VERSION}.tar.gz" -C /tmp \
    && cd "/tmp/NGT-${NGT_VERSION}" \
    && cmake -DNGT_LARGE_DATASET=ON . \
    && make -j -C "/tmp/NGT-${NGT_VERSION}" \
    && make install -C "/tmp/NGT-${NGT_VERSION}" \
    && cd /tmp \
    && rm -rf /tmp/*

FROM env-base AS tensorflow
WORKDIR /tmp
ENV TENSORFLOW_C_VERSION 2.9.0
RUN set -x; cd "$(mktemp -d)" \
    && REPO_NAME="tensorflow" \
    && BIN_NAME="lib${REPO_NAME}" \
    && REPO="${REPO_NAME}/${BIN_NAME}" \
    && if [ "${ARCH}" = "amd64" ] ; then  ARCH=${XARCH} ; fi \
    && URL="${GOOGLE}/${REPO}/${BIN_NAME}-cpu-${OS}-${ARCH}-${TENSORFLOW_C_VERSION}.tar.gz" \
    && echo "${URL}" \
    && curl -fsSLo "/tmp/${BIN_NAME}.tar.gz" "${URL}" \
    && tar -C /usr/local -xzf "/tmp/${BIN_NAME}.tar.gz" \
    && rm -rf /tmp/*

FROM env-base AS env

LABEL maintainer="kpango <kpango@vdaas.org>"

COPY --from=ngt ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --from=ngt ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --from=ngt ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
COPY --from=tensorflow ${LOCAL}/include/tensorflow ${LOCAL}/include/tensorflow
COPY --from=tensorflow ${LOCAL}/lib/libtensorflow* ${LOCAL}/lib/
COPY --from=protoc ${BIN_PATH}/protoc ${BIN_PATH}/protoc
COPY --from=protoc ${LOCAL}/include/google/protobuf ${LOCAL}/include/google/protobuf

RUN ldconfig \
    && rm -rf /tmp/* /var/cache

WORKDIR ${HOME}
