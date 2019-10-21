FROM kpango/dev-base:latest AS env

ENV NGT_VERSION 1.7.10
ENV HUB_VERSION 2.12.8
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/usr/x86_64-alpine-linux-musl/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib

RUN mkdir "/etc/ld.so.conf.d" \
    && echo $'/lib\n\
/lib64\n\
/var/lib\n\
/usr/lib\n\
/usr/local/lib\n\
/usr/x86_64-alpine-linux-musl/lib\n\
/usr/local/go/lib\n\
/usr/lib/dart/lib\n\
/usr/lib/node_modules/lib\n\
/google-cloud-sdk/lib' > /etc/ld.so.conf.d/usr-local-lib.conf \
    && echo $(ldconfig) \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && apk update \
    && apk upgrade \
    && apk --update add --no-cache --allow-untrusted --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    bash \
    clang \
    cmake \
    ctags \
    curl \
    diffutils \
    g++ \
    gawk \
    gcc \
    git \
    graphviz \
    hdf5 \
    hdf5-dev \
    jq \
    less \
    linux-headers \
    luajit \
    make \
    musl-dev \
    ncurses \
    neovim \
    nodejs \
    npm \
    openssh \
    openssl \
    openssl-dev \
    perl \
    protobuf \
    py-pip \
    py3-pip \
    python-dev \
    python3-dev \
    ruby-dev \
    tig \
    tmux \
    tzdata \
    xclip \
    yarn \
    zsh \
    zsh-vcs \
    && rm -rf /var/cache/apk/* \
    && pip2 install --upgrade pip neovim python-language-server vim-vint \
    && pip3 install --upgrade pip neovim ranger-fm thefuck httpie python-language-server vim-vint grpcio-tools \
    && gem install neovim -N \
    && npm config set user root \
    && npm install -g \
        neovim \
        resume-cli \
        markdownlint-cli \
        dockerfile-language-server-nodejs \
        typescript \
        typescript-language-server \
        bash-language-server \
    && cd /tmp \
    && git clone https://github.com/soimort/translate-shell \
    && cd /tmp/translate-shell/ \
    && make TARGET=zsh -j -C /tmp/translate-shell \
    && make install -C /tmp/translate-shell \
    && cd /tmp \
    && rm -rf /tmp/translate-shell/ \
    && curl -Lo ngt.tar.gz https://github.com/yahoojapan/NGT/archive/v${NGT_VERSION}.tar.gz \
    && tar zxf ngt.tar.gz -C /tmp \
    && rm -rf ngt.tar.gz \
    && cd /tmp/NGT-${NGT_VERSION} \
    && cmake . \
    && make -j -C /tmp/NGT-${NGT_VERSION} \
    && make install -C /tmp/NGT-${NGT_VERSION} \
    && cd /tmp \
    && rm -rf /tmp/NGT-${NGT_VERSION} \
    && curl -fsSLo hub.tar.gz "https://github.com/github/hub/releases/download/v${HUB_VERSION}/hub-linux-amd64-${HUB_VERSION}.tgz" \
    && tar zxf hub.tar.gz -C /tmp \

