# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS env-base

ARG TARGETOS
ARG TARGETARCH
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

ENV GITHUBCOM=github.com
ENV GITHUB=https://${GITHUBCOM}
ENV API_GITHUB=https://api.${GITHUBCOM}/repos
ENV RAWGITHUB=https://raw.githubusercontent.com
ENV GOOGLE=https://storage.googleapis.com
ENV RELEASE_DL=releases/download
ENV RELEASE_LATEST=releases/latest
ENV LOCAL=/usr/local
ENV BIN_PATH=${LOCAL}/bin

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG GROUP_IDS=${GROUP_ID}

ENV LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:/lib:/lib64:/var/lib:/google-cloud-sdk/lib:/usr/local/go/lib:/usr/lib/dart/lib:/usr/lib/node_modules/lib
ENV BASE_DIR=/home
ENV USER=${WHOAMI}
ENV HOME=${BASE_DIR}/${USER}
ENV SHELL=/usr/bin/zsh
ENV GROUP=sudo,root,users,docker,wheel
ENV UID=${USER_ID}

RUN groupadd --non-unique --gid ${GROUP_ID} docker \
    && groupadd --non-unique --gid ${GROUP_ID} wheel \
    && groupmod --non-unique --gid ${GROUP_ID} users \
    && useradd --uid ${USER_ID} \
        --gid ${GROUP_ID} \
        --non-unique --create-home \
        --shell ${SHELL} \
        --base-dir ${BASE_DIR} \
        --home ${HOME} \
        --groups ${GROUP} ${USER} \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && sed -i -e 's/# %users\tALL=(ALL)\tNOPASSWD: ALL/%users\tALL=(ALL)\tNOPASSWD: ALL/' /etc/sudoers \
    && sed -i -e 's/%users\tALL=(ALL)\tALL/# %users\tALL=(ALL)\tALL/' /etc/sudoers \
    && chown -R 0:0 /etc/sudoers.d \
    && chown -R 0:0 /etc/sudoers \
    && chmod -R 0440 /etc/sudoers.d \
    && chmod -R 0440 /etc/sudoers \
    && visudo -c

WORKDIR /tmp
RUN --mount=type=cache,target=${HOME}/.bun \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo '/lib\n\
/lib64\n\
/var/lib\n\
/usr/lib\n\
/usr/local/lib\n\
/usr/local/go/lib\n\
/usr/local/clang/lib\n\
/usr/lib/dart/lib\n\
/usr/lib/node_modules/lib\n\
/google-cloud-sdk/lib' > /etc/ld.so.conf.d/usr-local-lib.conf \
    && ldconfig \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
    && echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 https://github.com/soimort/translate-shell \
    && cd /tmp/translate-shell/ \
    && make TARGET=zsh -j -C /tmp/translate-shell \
    && make install -C /tmp/translate-shell \
    && cd /tmp \
    && rm -rf /tmp/translate-shell/ \
    && chown -R ${USER}:users ${HOME} \
    && chown -R ${USER}:users ${HOME}/.* \
    && chmod -R 755 ${HOME} \
    && chmod -R 755 ${HOME}/.* \
    && export BUN_INSTALL=${LOCAL} && curl -fsSL https://bun.sh/install | bash

USER root
FROM env-base AS protoc
WORKDIR /tmp
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && REPO_NAME="protobuf" \
    && BIN_NAME="protoc" \
    && REPO="protocolbuffers/${REPO_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; arm64) ARCH="aarch_64" ;; esac \
    && ZIP_NAME="${BIN_NAME}-${VERSION}-${OS}-${ARCH}" \
    && curl -fsSLo "/tmp/${BIN_NAME}.zip" "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${ZIP_NAME}.zip" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local "bin/${BIN_NAME}" \
    && unzip -o "/tmp/${BIN_NAME}.zip" -d /usr/local 'include/*' \
    && rm -f /tmp/protoc.zip \
    && rm -rf /tmp/*

FROM env-base AS zig_tools
WORKDIR /tmp
# Install Zig
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && REPO_NAME="ziglang" \
    && BIN_NAME="zig" \
    && REPO="${REPO_NAME}/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; arm64) ARCH=${AARCH} ;; esac \
    && TAR_NAME="${BIN_NAME}-${ARCH}-${OS}-${VERSION}" \
    && curl -fsSLo "/tmp/${BIN_NAME}.tar.xz" "https://${REPO_NAME}.org/download/${VERSION}/${TAR_NAME}.tar.xz" \
    && tar -xf "/tmp/${BIN_NAME}.tar.xz" -C /tmp \
    && mv "/tmp/${TAR_NAME}/${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && rm -rf "/tmp/${BIN_NAME}.tar.xz" \
    && rm -rf "/tmp/${TAR_NAME}" \
    && chmod +x "${BIN_PATH}/${BIN_NAME}"

# Install ZLS (Zig Language Server)
RUN --mount=type=secret,id=gat set -x && cd "$(mktemp -d)" \
    && REPO_NAME="zigtools" \
    && BIN_NAME="zls" \
    && REPO="${REPO_NAME}/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$(curl -fsSLGH "${HEADER}" ${API_GITHUB}/${REPO}/${RELEASE_LATEST} || curl -fsSL ${API_GITHUB}/${REPO}/${RELEASE_LATEST}) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] || { echo "Error: VERSION is empty. Curl response was: ${BODY}" >&2; exit 1; } \
    && case "${ARCH}" in amd64) ARCH=${XARCH} ;; arm64) ARCH=${AARCH} ;; esac \
    && TAR_NAME="${BIN_NAME}-${ARCH}-${OS}" \
    && curl -fsSLo "./${BIN_NAME}.tar.xz" "${GITHUB}/${REPO}/${RELEASE_DL}/${VERSION}/${TAR_NAME}.tar.xz" \
    && tar -xf "./${BIN_NAME}.tar.xz" -C . \
    && mv "./${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && rm -rf "./${BIN_NAME}.tar.xz" \
    && rm -rf ./* \
    && chmod +x "${BIN_PATH}/${BIN_NAME}"

FROM env-base AS cmake-base
WORKDIR /tmp
RUN git clone --depth 1 https://github.com/vdaas/vald "/tmp/vald" \
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

FROM env-base AS env-stage
WORKDIR /tmp
ENV PATH=${LOCAL}/bin:${PATH}
ENV BUN_INSTALL=/usr/local
RUN --mount=type=cache,target=/root/.bun/install/cache \
    BUN_INSTALL=${BUN_INSTALL} bun install -g \
        prettier \
        pyright \
        markdownlint-cli \
        dockerfile-language-server-nodejs \
        bash-language-server \
        typescript \
        typescript-language-server \
        n \
        opencode-ai \
        @anthropic-ai/claude-code \
        @byterover/cipher \
        @github/copilot \
        @google/gemini-cli \
        @google/jules \
        @openai/codex \
        @qwen-code/qwen-code \
        yaml-language-server \
    && ${BUN_INSTALL}/bin/n latest
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install mbake beautysh --prefix /usr

FROM env-stage AS env
ARG EMAIL=kpango@vdaas.org
ARG WHOAMI=kpango
LABEL maintainer="${WHOAMI} <${EMAIL}>"

COPY --link --from=ngt ${BIN_PATH}/ng* ${BIN_PATH}/
COPY --link --from=ngt ${LOCAL}/include/NGT ${LOCAL}/include/NGT
COPY --link --from=ngt ${LOCAL}/lib/libngt.* ${LOCAL}/lib/
COPY --link --from=faiss ${LOCAL}/include/faiss ${LOCAL}/include/faiss
COPY --link --from=faiss ${LOCAL}/lib/libfaiss.* ${LOCAL}/lib/
COPY --link --from=usearch ${LOCAL}/include/usearch.h ${LOCAL}/include/usearch.h
COPY --link --from=usearch ${LOCAL}/lib/libusearch* ${LOCAL}/lib/
COPY --link --from=protoc ${BIN_PATH}/protoc ${BIN_PATH}/protoc
COPY --link --from=protoc ${LOCAL}/include/google/protobuf ${LOCAL}/include/google/protobuf
COPY --link --from=zig_tools \
    ${BIN_PATH}/zig \
    ${BIN_PATH}/zls \
    ${BIN_PATH}/

RUN ldconfig \
    && rm -rf /tmp/* /var/cache

WORKDIR ${HOME}
