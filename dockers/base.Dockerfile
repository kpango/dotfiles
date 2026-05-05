# syntax = docker/dockerfile:latest

ARG CURL_RETRY=3
ARG CURL_RETRY_DELAY=3

FROM ubuntu:devel AS base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
ARG CURL_RETRY
ARG CURL_RETRY_DELAY
LABEL maintainer="${WHOAMI} <${EMAIL}>"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV OS=${TARGETOS} \
    ARCH=${TARGETARCH} \
    CURL_RETRY=${CURL_RETRY} \
    CURL_RETRY_DELAY=${CURL_RETRY_DELAY} \
    XARCH=x86_64 \
    AARCH=aarch64 \
    DEBIAN_FRONTEND=noninteractive \
    INITRD=No \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=Asia/Tokyo \
    CC=/usr/bin/clang \
    CXX=/usr/bin/clang++ \
    CLANG_PATH=/usr/local/clang \
    GOOGLE=https://storage.googleapis.com \
    RELEASE_DL=releases/download \
    RELEASE_LATEST=releases/latest \
    LOCAL=/usr/local \
    GITHUBCOM=github.com \
    GITHUB=https://github.com \
    API_GITHUB=https://api.github.com/repos \
    RAWGITHUB=https://raw.githubusercontent.com \
    BIN_PATH=/usr/local/bin
ENV PATH=${PATH}:${CLANG_PATH}/bin \
    LD_LIBRARY_PATH=${CLANG_PATH}/lib

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/no-install-recommends

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=secret,id=gat \
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
        universal-ctags \
        g++ \
        gawk \
        gcc \
        gcc-aarch64-linux-gnu \
        gcc-x86-64-linux-gnu \
        gettext \
        gfortran \
        git \
        gnupg2 \
        jq \
        less \
        libfp16-dev \
        libhdf5-serial-dev \
        libncurses-dev \
        libomp-dev \
        libssl-dev \
        libtool-bin \
        libx11-dev \
        libxcb-composite0-dev \
        lld \
        llvm \
        locales \
        lua5.4 \
        luajit \
        luarocks \
        mtr \
        ncurses-term \
        nkf \
        openssh-client \
        pass \
        perl \
        pinentry-tty \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
        sed \
        software-properties-common \
        sudo \
        tar \
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
    && GITHUB_TOKEN=$(cat /run/secrets/gat) \
       git config --global \
       url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/" \
    && update-alternatives --set cc "$(which clang)" \
    && update-alternatives --set c++ "$(which clang++)" \
    && echo "${LANG} UTF-8" > /etc/locale.gen \
    && ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
    && locale-gen \
    && rm /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata
