# syntax = docker/dockerfile:latest
FROM --platform=$BUILDPLATFORM ubuntu:devel AS base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV OS=${TARGETOS}
ENV ARCH=${TARGETARCH}
ENV XARCH x86_64
ENV AARCH aarch64
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

RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/no-install-recommends \
    && apt clean\
    && rm -rf \
        /var/lib/apt/lists/* \
        /var/cache/* \
    && apt update -y \
    && apt upgrade -y \
    && apt install -y --no-install-recommends --fix-missing \
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
        libx11-dev \
        libxcb-composite0-dev \
        locales \
        pandoc \
        pkg-config \
        poppler-utils \
        python3 \
        sudo \
        tzdata \
        unzip \
        upx \
        wget \
        xz-utils \
        zsh \
    && update-alternatives --set cc $(which clang) \
    && update-alternatives --set c++ $(which clang++) \
    && apt clean -y \
    && apt autoclean -y \
    && rm -rf /var/lib/apt/lists/* \
    && echo "${LANG} UTF-8" > /etc/locale.gen \
    && ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
    && locale-gen \
    && rm /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && apt autoremove -y
