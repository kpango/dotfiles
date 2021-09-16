FROM --platform=$BUILDPLATFORM ubuntu:latest AS base

LABEL maintainer="kpango <kpango@vdaas.org>"

ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV TZ Asia/Tokyo
ENV CC /usr/bin/clang
ENV CXX /usr/bin/clang++
ENV CLANG_PATH /usr/local/clang
ENV PATH ${PATH}:${CLANG_PATH}/bin
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:${CLANG_PATH}/lib

RUN apt-get update -y \
    && apt-get upgrade -y \
    && apt-get dist-upgrade -y \
    && apt-get install -y --no-install-recommends --fix-missing \
        axel \
        build-essential \
        ca-certificates \
        clang \
        cmake \
        curl \
        ffmpeg \
        git \
        gnupg \
        libssl-dev \
        libtinfo5 \
        libx11-dev \
        libxcb-composite0-dev \
        locales \
        pandoc \
        pkg-config \
        poppler-utils \
        python3 \
        python2 \
        sudo \
        tzdata \
        unzip \
        upx \
        wget \
        xz-utils \
        zsh \
    && update-alternatives --set cc $(which clang) \
    && update-alternatives --set c++ $(which clang++) \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "${LANG} UTF-8" > /etc/locale.gen \
    && ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
    && locale-gen \
    && rm /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && apt autoremove
