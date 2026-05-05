# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS vald-base

ARG TARGETOS
ARG TARGETARCH

FROM vald-base AS cmake-base
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -y \
    && apt-get install -y --no-install-recommends \
       liblapack-dev \
       libopenblas-dev \
       libhdf5-dev \
       libaec-dev
WORKDIR /tmp
RUN git clone --depth 1 ${GITHUB}/vdaas/vald "/tmp/vald" \
    && cd "/tmp/vald" \
    && make cmake/install

FROM cmake-base AS ngt
WORKDIR /tmp/vald
RUN make ngt/install

FROM cmake-base AS faiss
WORKDIR /tmp/vald
RUN make faiss/install

FROM cmake-base AS usearch
WORKDIR /tmp/vald
RUN make usearch/install

FROM scratch AS vald
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV LOCAL=/usr/local
ENV BIN_PATH=${LOCAL}/bin

COPY --link --from=ngt ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --link --from=ngt ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --link --from=ngt ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
COPY --link --from=faiss ${LOCAL}/include/faiss ${LOCAL}/include/faiss
COPY --link --from=faiss ${LOCAL}/lib/libfaiss.* ${LOCAL}/lib/
COPY --link --from=usearch ${LOCAL}/include/usearch.h ${LOCAL}/include/usearch.h
COPY --link --from=usearch ${LOCAL}/lib/libusearch* ${LOCAL}/lib/
