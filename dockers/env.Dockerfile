FROM kpango/dev-base:latest AS env

ENV NGT_VERSION 1.9.1
ENV TENSORFLOW_C_VERSION 1.13.1
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib

WORKDIR /tmp
RUN echo $'/lib\n\
/lib64\n\
/var/lib\n\
/usr/lib\n\
/usr/local/lib\n\
/usr/local/go/lib\n\
/usr/local/clang/lib\n\
/usr/lib/dart/lib\n\
/usr/lib/node_modules/lib\n\
/google-cloud-sdk/lib' > /etc/ld.so.conf.d/usr-local-lib.conf \
    && echo $(ldconfig)

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    ctags \
    diffutils \
    gawk \
    graphviz \
    libhdf5-serial-dev \
    jq \
    less \
    luajit \
    neovim \
    nodejs \
    npm \
    ssh \
    perl \
    libprotobuf-dev \
    libprotoc-dev \
    protobuf-compiler \
    python3-dev \
    python3-setuptools \
    python3-pip \
    python3-venv \
    ruby-dev \
    tar \
    tig \
    tmux \
    tzdata \
    xclip \
    yarn \
    zsh

RUN pip3 install --upgrade pip neovim ranger-fm thefuck httpie python-language-server vim-vint grpcio-tools \
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
    && git clone https://github.com/soimort/translate-shell \
    && cd /tmp/translate-shell/ \
    && make TARGET=zsh -j -C /tmp/translate-shell \
    && make install -C /tmp/translate-shell \
    && cd /tmp \
    && rm -rf /tmp/translate-shell/

RUN git clone https://github.com/yahoojapan/NGT -b v${NGT_VERSION} --depth 1 \
    && cd /tmp/NGT \
    && mkdir build \
    && cd build \
    && cmake -DNGT_LARGE_DATASET=ON -DNGT_OPENMP_DISABLE=1 .. \
    && make  \
    && make install \
    && cd /tmp \
    && rm -rf /tmp/NGT

WORKDIR /tmp
RUN curl -LO https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-linux-x86_64-${TENSORFLOW_C_VERSION}.tar.gz \
	&& tar -C /usr/local -xzf libtensorflow-cpu-linux-x86_64-${TENSORFLOW_C_VERSION}.tar.gz \
	&& rm -f libtensorflow-cpu-linux-x86_64-${TENSORFLOW_C_VERSION}.tar.gz \
	&& ldconfig \
    && rm -rf /tmp/* /var/cache
