# syntax = docker/dockerfile:latest
FROM nimlang/nim:latest AS nim

ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV BASE_DIR=/home
ENV USER=${WHOAMI}
ENV HOME=${BASE_DIR}/${USER}
USER ${USER}
RUN nimble install nimlangserver -y
