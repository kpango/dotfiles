# syntax = docker/dockerfile:latest
FROM ubuntu:devel AS base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV XARCH=x86_64
ENV AARCH=aarch64
ENV DEBIAN_FRONTEND=noninteractive
ENV INITRD=No
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TZ=Asia/Tokyo
ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++
ENV CLANG_PATH=/usr/local/clang
ENV PATH=${PATH}:${CLANG_PATH}/bin
ENV LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${CLANG_PATH}/lib
ENV GITHUBCOM=github.com
ENV GITHUB=https://${GITHUBCOM}
ENV API_GITHUB=https://api.github.com/repos
ENV RAWGITHUB=https://raw.githubusercontent.com
ENV GOOGLE=https://storage.googleapis.com
ENV RELEASE_DL=releases/download
ENV RELEASE_LATEST=releases/latest
ENV LOCAL=/usr/local
ENV BIN_PATH=${LOCAL}/bin

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/no-install-recommends

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -y \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends --fix-missing \
        axel \
        build-essential \
        ca-certificates \
        clang \
        clang-format \
        clang-tidy \
        clangd \
        cmake \
        curl \
        diffutils \
        exuberant-ctags \
        ffmpeg \
        g++ \
        gawk \
        gcc \
        gcc-aarch64-linux-gnu \
        gcc-x86-64-linux-gnu \
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
        libncurses-dev \
        libomp-dev \
        libopenblas-dev \
        libssl-dev \
        libtool \
        libtool-bin \
        libx11-dev \
        libxcb-composite0-dev \
        lld \
        llvm \
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
        pandoc \
        pass \
        perl \
        pinentry-tty \
        pkg-config \
        poppler-utils \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
        ruby-dev \
        sass \
        sed \
        software-properties-common \
        sudo \
        tar \
        tig \
        tmux \
        tzdata \
        ugrep \
        unzip \
        upx \
        wget \
        xclip \
        xz-utils \
        zip \
        zsh \
    && update-alternatives --set cc "$(which clang)" \
    && update-alternatives --set c++ "$(which clang++)" \
    && apt-get clean -y \
    && apt-get autoclean -y \
    && rm -rf /var/lib/apt/lists/* \
    && echo "${LANG} UTF-8" > /etc/locale.gen \
    && ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
    && locale-gen \
    && rm /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && apt-get autoremove -y
