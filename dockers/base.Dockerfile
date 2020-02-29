FROM ubuntu:latest AS base

ENV DEBIAN_FRONTEND noninteractive
ENV INITRD No
ENV LANG en_US.UTF-8
ENV CC clang
ENV CXX clang++
ENV LLVM_VERSION 9.0.0
ENV CLANG_PATH /usr/local/clang
ENV PATH ${PATH}:${CLANG_PATH}/bin
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:${CLANG_PATH}/lib


RUN echo ${LANG} UTF-8 > /etc/locale.gen \
    && ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        libtinfo5 \
        wget \
        cmake \
        curl \
        axel \
        git \
        zsh \
        unzip \
        upx \
        xz-utils

RUN curl -fsSL http://releases.llvm.org/${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-18.04.tar.xz -o clang.tar.xz \
    && tar -xf clang.tar.xz \
    && rm -rf clang.tar.xz \
    && mv clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-18.04 ${CLANG_PATH}
