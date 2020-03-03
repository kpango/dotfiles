FROM ubuntu:devel AS base

ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV TZ Asia/Tokyo
ENV CC clang
ENV CXX clang++
ENV CLANG_PATH /usr/local/clang
ENV PATH ${PATH}:${CLANG_PATH}/bin
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:${CLANG_PATH}/lib

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        clang \
        axel \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libtinfo5 \
        locales \
        unzip \
        upx \
        wget \
        xz-utils \
        zsh \
        tzdata \
    && update-alternatives --set cc $(which clang) \
    && update-alternatives --set c++ $(which clang++) \
    && rm -rf /var/lib/apt/lists/*

RUN echo "${LANG} UTF-8" > /etc/locale.gen \
    && ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
    && locale-gen \
    && rm /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata

