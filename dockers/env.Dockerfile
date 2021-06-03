FROM kpango/dev-base:latest AS env
LABEL maintainer="kpango <kpango@vdaas.org>"

ARG USER_ID=1000
ARG GROUP_ID=985
ARG GROUP_IDS=${GROUP_ID}
ARG WHOAMI=kpango

ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib
ENV BASE_DIR /home
ENV USER ${WHOAMI}
ENV HOME ${BASE_DIR}/${USER}
ENV SHELL /usr/bin/zsh
ENV GROUP sudo,root,users
ENV UID ${USER_ID}

RUN useradd --uid ${USER_ID} --create-home --shell ${SHELL} --base-dir ${BASE_DIR} --home ${HOME} ${USER} \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && sed -i -e 's/# %users\tALL=(ALL)\tNOPASSWD: ALL/%users\tALL=(ALL)\tNOPASSWD: ALL/' /etc/sudoers \
    && sed -i -e 's/%users\tALL=(ALL)\tALL/# %users\tALL=(ALL)\tALL/' /etc/sudoers \
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
    automake \
    bash \
    diffutils \
    exuberant-ctags \
    gawk \
    graphviz \
    gettext \
    jq \
    sass \
    less \
    libhdf5-serial-dev \
    libncurses5-dev \
    libomp-dev \
    libprotobuf-dev \
    libprotoc-dev \
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
    protobuf-compiler \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-venv \
    ruby-dev \
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

WORKDIR /tmp
ENV NGT_VERSION 1.13.7
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

WORKDIR /tmp
ENV TENSORFLOW_C_VERSION 2.4.0
RUN curl -LO https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-linux-x86_64-${TENSORFLOW_C_VERSION}.tar.gz \
    && tar -C /usr/local -xzf libtensorflow-cpu-linux-x86_64-${TENSORFLOW_C_VERSION}.tar.gz \
    && rm -f libtensorflow-cpu-linux-x86_64-${TENSORFLOW_C_VERSION}.tar.gz \
    && ldconfig \
    && rm -rf /tmp/* /var/cache

WORKDIR ${HOME}
