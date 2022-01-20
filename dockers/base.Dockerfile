FROM --platform=$BUILDPLATFORM ubuntu:devel AS base

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

RUN apt clean\
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
        intel-mkl \
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
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/libblas.so  \
       libblas.so-x86_64-linux-gnu      /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/libblas.so.3  \
       libblas.so.3-x86_64-linux-gnu    /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/libblas64.so  \
       libblas64.so-x86_64-linux-gnu      /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/libblas64.so.3  \
       libblas64.so.3-x86_64-linux-gnu    /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/liblapack.so  \
       liblapack.so-x86_64-linux-gnu      /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/liblapack.so.3  \
       liblapack.so.3-x86_64-linux-gnu    /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/liblapack64.so  \
       liblapack64.so-x86_64-linux-gnu      /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && update-alternatives --install /usr/lib/x86_64-linux-gnu/mkl/liblapack64.so.3  \
       liblapack64.so.3-x86_64-linux-gnu    /usr/lib/x86_64-linux-gnu/libmkl_rt.so 150 \
    && apt clean -y \
    && apt autoclean -y \
    && rm -rf /var/lib/apt/lists/* \
    && echo "${LANG} UTF-8" > /etc/locale.gen \
    && ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
    && locale-gen \
    && rm /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && apt autoremove -y
