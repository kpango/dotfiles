# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS rust-base

ENV HOME=/root \
    RUST_HOME=/usr/local/lib/rust
ENV CARGO_HOME=${RUST_HOME}/cargo \
    RUSTUP_HOME=${RUST_HOME}/rustup
ENV BIN_PATH=${CARGO_HOME}/bin \
    PATH=${CARGO_HOME}/bin:${PATH} \
    CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CARGO_INCREMENTAL=0 \
    RUSTFLAGS="-C opt-level=z -C strip=symbols -C codegen-units=1"

RUN --mount=type=cache,target=${RUSTUP_HOME}/downloads,sharing=locked \
    curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs \
    | CARGO_HOME=${CARGO_HOME} RUSTUP_HOME=${RUSTUP_HOME} sh -s -- --default-toolchain nightly -y \
    && CARGO_HOME=${CARGO_HOME} RUSTUP_HOME=${RUSTUP_HOME} ${CARGO_HOME}/bin/rustup install stable \
    && CARGO_HOME=${CARGO_HOME} RUSTUP_HOME=${RUSTUP_HOME} ${CARGO_HOME}/bin/rustup default nightly \
    && CARGO_HOME=${CARGO_HOME} RUSTUP_HOME=${RUSTUP_HOME} ${CARGO_HOME}/bin/rustup update \
    && CARGO_HOME=${CARGO_HOME} RUSTUP_HOME=${RUSTUP_HOME} ${CARGO_HOME}/bin/rustup component add \
       clippy \
       rust-analyzer \
       rustfmt \
       rust-src \
       --toolchain nightly \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL --proto '=https' --tlsv1.2 ${RAWGITHUB}/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
        | bash

FROM rust-base AS rust-stable
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=cache,target=${RUSTUP_HOME}/downloads,sharing=locked \
    rustup update stable && rustup default stable

FROM rust-base AS cargo-asm
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-asm \
    && upx --best ${BIN_PATH}/cargo-asm || true

FROM rust-base AS cargo-binutils
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-binutils \
    && upx --best ${BIN_PATH}/cargo-* ${BIN_PATH}/rust-* || true

FROM rust-base AS cargo-bloat
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-bloat \
    && upx --best ${BIN_PATH}/cargo-bloat || true

FROM rust-base AS cargo-check
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-check \
    && upx --best ${BIN_PATH}/cargo-check || true

FROM rust-base AS cargo-edit
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-edit \
    && upx --best ${BIN_PATH}/cargo-add ${BIN_PATH}/cargo-rm ${BIN_PATH}/cargo-set-version ${BIN_PATH}/cargo-upgrade || true

FROM rust-base AS cargo-expand
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-expand \
    && upx --best ${BIN_PATH}/cargo-expand || true

FROM rust-base AS cargo-fix
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    cargo-fix \
    && upx --best ${BIN_PATH}/cargo-fix || true

FROM rust-base AS cargo-machete
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    cargo-machete \
    && upx --best ${BIN_PATH}/cargo-machete || true

FROM rust-base AS cargo-tree
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-tree \
    && upx --best ${BIN_PATH}/cargo-tree || true

FROM rust-base AS cargo-watch
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-watch \
    && upx --best ${BIN_PATH}/cargo-watch || true

FROM rust-base AS ast-grep
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    ast-grep \
    && upx --best ${BIN_PATH}/sg || true

FROM rust-stable AS atuin
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    atuin \
    && upx --best ${BIN_PATH}/atuin || true

FROM rust-base AS bandwhich
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    bandwhich \
    && upx --best ${BIN_PATH}/bandwhich || true

FROM rust-stable AS bat
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    bat \
    && upx --best ${BIN_PATH}/bat || true

FROM rust-stable AS bottom
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    bottom \
    && upx --best ${BIN_PATH}/btm || true

FROM rust-base AS broot
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    broot \
    && upx --best ${BIN_PATH}/broot || true

FROM rust-stable AS cpz
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    cpz \
    && upx --best ${BIN_PATH}/cpz || true

FROM rust-base AS delta
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    git-delta \
    && upx --best ${BIN_PATH}/delta || true

FROM rust-stable AS deno
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y deno \
    && (upx --best ${BIN_PATH}/deno || true) \
    || { cd "$(mktemp -d)" \
        && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
        && BODY=$( \
            curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/denoland/deno/${RELEASE_LATEST}" \
            || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/denoland/deno/${RELEASE_LATEST}" \
        ) \
        && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
        && [ -n "${VERSION}" ] && [ "${VERSION}" != "null" ] \
        && case "${ARCH}" in amd64) DENO_ARCH="x86_64" ;; arm64|aarch64) DENO_ARCH="aarch64" ;; *) DENO_ARCH="x86_64" ;; esac \
        && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${GITHUB}/denoland/deno/${RELEASE_DL}/v${VERSION}/deno-${DENO_ARCH}-unknown-linux-gnu.zip" \
        && unzip deno-*.zip \
        && mv deno "${BIN_PATH}/deno" \
        && chmod a+x "${BIN_PATH}/deno" \
        && (upx --best "${BIN_PATH}/deno" || true) \
        ; }


FROM rust-base AS dutree
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    dutree \
    && upx --best ${BIN_PATH}/dutree || true

FROM rust-base AS erdtree
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    erdtree \
    && upx --best ${BIN_PATH}/erd || true

FROM rust-stable AS eza
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    eza \
    && upx --best ${BIN_PATH}/eza || true

FROM rust-base AS fd
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y fd-find \
    && upx --best ${BIN_PATH}/fd || true

FROM rust-base AS frawk
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    export GITHUB_TOKEN=$(cat /run/secrets/gat) \
    && case "${ARCH}" in amd64|x86_64) FRAWK_FEATURES="use_jemalloc,allow_avx2" ;; *) FRAWK_FEATURES="use_jemalloc" ;; esac \
    && cargo install \
    --no-default-features --features "${FRAWK_FEATURES}" \
    --git ${GITHUB}/ezrosent/frawk frawk \
    && upx --best ${BIN_PATH}/frawk || true

FROM rust-stable AS gping
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    gping \
    && upx --best ${BIN_PATH}/gping || true

FROM rust-base AS helix
ENV HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime
RUN --mount=type=secret,id=gat \
    set -x && cd "$(mktemp -d)" \
    && REPO="helix-editor/helix" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] && [ "${VERSION}" != "null" ] \
        || { echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; exit 1; } \
    && case "${ARCH}" in amd64) HX_ARCH="x86_64" ;; arm64|aarch64) HX_ARCH="aarch64" ;; *) HX_ARCH="x86_64" ;; esac \
    && TAR_NAME="helix-${VERSION}-${HX_ARCH}-linux" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/${VERSION}/${TAR_NAME}.tar.xz" \
    && tar -xJf "${TAR_NAME}.tar.xz" \
    && install -m 755 "${TAR_NAME}/hx" "${BIN_PATH}/hx" \
    && mkdir -p "${HELIX_DEFAULT_RUNTIME}" \
    && cp -r "${TAR_NAME}/runtime" "${HELIX_DEFAULT_RUNTIME}" \
    && (upx --best "${BIN_PATH}/hx" || true)

FROM rust-base AS herdr
RUN --mount=type=secret,id=gat \
  set -ex \
  && case "${ARCH}" in \
      amd64|x86_64) NATIVE_ARCH="x86_64" ;; \
      arm64|aarch64) NATIVE_ARCH="aarch64" ;; \
      *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
  esac \
  && BIN_NAME="herdr" \
  && REPO="ogulcancelik/${BIN_NAME}" \
  && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
  && BODY=$( \
      curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
      || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
  ) \
  && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
  && [ -n "${VERSION}" ] \
  && [ "${VERSION}" != "null" ] \
      || { \
          echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
          exit 1; \
      } \
  && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-linux-${NATIVE_ARCH}" \
  && echo ${URL} \
  && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo ${BIN_NAME} "${URL}" \
  && chmod +x ${BIN_NAME} \
  && mv ${BIN_NAME} "${BIN_PATH}/${BIN_NAME}" \
  && upx --best ${BIN_PATH}/herdr || true

FROM rust-base AS hx-lsp
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    hx-lsp \
    && upx --best ${BIN_PATH}/hx-lsp || true

FROM rust-base AS hyperfine
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    hyperfine \
    && upx --best ${BIN_PATH}/hyperfine || true

FROM rust-base AS leaf
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install --git ${GITHUB}/RivoLink/leaf \
    && upx --best ${BIN_PATH}/leaf || true

FROM rust-base AS lsd
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y lsd \
    && upx --best ${BIN_PATH}/lsd || true

FROM rust-base AS lsp-ai
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=secret,id=gat \
  set -ex \
  && case "${ARCH}" in \
      amd64|x86_64) NATIVE_ARCH="x86_64" ;; \
      arm64|aarch64) NATIVE_ARCH="aarch64" ;; \
      *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
  esac \
  && BIN_NAME="lsp-ai" \
  && REPO="SilasMarvin/${BIN_NAME}" \
  && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
  && BODY=$( \
      curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
      || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
  ) \
  && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
  && [ -n "${VERSION}" ] \
  && [ "${VERSION}" != "null" ] \
      || { \
          echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; \
          exit 1; \
      } \
  && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-${NATIVE_ARCH}-unknown-linux-gnu.gz" \
  && echo ${URL} \
  && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo ${BIN_NAME}.gz "${URL}" \
  && gzip -d ${BIN_NAME}.gz \
  && chmod +x ${BIN_NAME} \
  && mv ${BIN_NAME} "${BIN_PATH}/${BIN_NAME}" \
  && upx --best ${BIN_PATH}/lsp-ai || true


FROM rust-base AS nushell
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y nu \
    && upx --best ${BIN_PATH}/nu || true

FROM rust-stable AS pay-respects
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    pay-respects \
    && upx --best ${BIN_PATH}/pay-respects || true

FROM rust-base AS prek
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    prek \
    && upx --best ${BIN_PATH}/prek || true

FROM rust-base AS prmt
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    prmt \
    && upx --best ${BIN_PATH}/prmt || true

FROM rust-base AS procs
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y procs \
    && upx --best ${BIN_PATH}/procs || true

FROM rust-stable AS rg
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    ripgrep \
    && upx --best ${BIN_PATH}/rg || true

FROM rg AS rga
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    ripgrep_all \
    && upx --best ${BIN_PATH}/rga || true

FROM rust-stable AS rmz
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    rmz \
    && upx --best ${BIN_PATH}/rmz || true


FROM rust-base AS rtk
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git ${GITHUB}/rtk-ai/rtk \
    && upx --best ${BIN_PATH}/rtk || true

FROM rust-base AS sad
RUN --mount=type=secret,id=gat \
    set -x && cd "$(mktemp -d)" \
    && BIN_NAME="sad" \
    && REPO="ms-jpq/${BIN_NAME}" \
    && HEADER="Authorization: Bearer $(cat /run/secrets/gat)" \
    && BODY=$( \
        curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLGH "${HEADER}" "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
        || curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL "${API_GITHUB}/${REPO}/${RELEASE_LATEST}" \
    ) \
    && VERSION=$(echo "${BODY}" | jq -r .tag_name | sed 's/^v//') \
    && [ -n "${VERSION}" ] && [ "${VERSION}" != "null" ] \
        || { echo "Error: VERSION is empty or null. Curl response was: ${BODY}" >&2; exit 1; } \
    && case "${ARCH}" in amd64) SAD_ARCH="x86_64" ;; arm64|aarch64) SAD_ARCH="aarch64" ;; *) SAD_ARCH="x86_64" ;; esac \
    && TAR_NAME="${BIN_NAME}-${SAD_ARCH}-unknown-linux-musl" \
    && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLO "${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${TAR_NAME}.tar.gz" \
    && tar -zxvf "${TAR_NAME}.tar.gz" \
    && install -m 755 "${BIN_NAME}" "${BIN_PATH}/${BIN_NAME}" \
    && (upx --best "${BIN_PATH}/${BIN_NAME}" || true)

FROM rust-base AS sd
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    sd \
    && upx --best ${BIN_PATH}/sd || true

FROM rust-base AS sheldon
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y sheldon \
    && upx --best ${BIN_PATH}/sheldon || true

FROM rust-base AS shellharden
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    shellharden \
    && upx --best ${BIN_PATH}/shellharden || true

FROM rust-base AS starship
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y starship \
    && upx --best ${BIN_PATH}/starship || true

FROM rust-base AS stylua
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y stylua \
    && upx --best ${BIN_PATH}/stylua || true

FROM rust-base AS tokei
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y tokei \
    && upx --best ${BIN_PATH}/tokei || true

FROM rust-base AS t-rec
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    t-rec \
    && upx --best ${BIN_PATH}/t-rec || true

FROM rust-base AS tree-sitter
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    tree-sitter-cli \
    && upx --best ${BIN_PATH}/tree-sitter || true

FROM rust-base AS typos-lsp
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly install \
    --git ${GITHUB}/tekumara/typos-lsp --locked typos-lsp \
    && upx --best ${BIN_PATH}/typos-lsp || true

FROM rust-stable AS watchexec
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y watchexec-cli \
    && upx --best ${BIN_PATH}/watchexec || true

FROM rust-base AS xh
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) \
    RUSTFLAGS="${RUSTFLAGS} --cfg reqwest_unstable" \
    cargo +nightly binstall -y \
    xh \
    && upx --best ${BIN_PATH}/xh || true

FROM rust-stable AS zoxide
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    zoxide \
    && upx --best ${BIN_PATH}/zoxide || true

FROM rust-stable AS zsh-patina
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    zsh-patina \
    && upx --best ${BIN_PATH}/zsh-patina || true

FROM rust-base AS rust-base-bins
RUN find ${CARGO_HOME}/bin -maxdepth 1 -type f -executable \
    ! -name 'rustc' ! -name 'rustup' ! -name 'rust-analyzer' \
    | xargs -P $(nproc) -n 1 sh -c 'upx --best "$1" 2>/dev/null || true' --

FROM scratch AS rust
ENV RUST_HOME=/usr/local/lib/rust \
    HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime
ENV CARGO_HOME=${RUST_HOME}/cargo \
    RUSTUP_HOME=${RUST_HOME}/rustup
ENV BIN_PATH=${CARGO_HOME}/bin

COPY --link --from=rust-base-bins ${CARGO_HOME}/bin ${CARGO_HOME}/bin
COPY --link --from=rust-base ${RUSTUP_HOME} ${RUSTUP_HOME}
COPY --link --from=cargo-asm ${BIN_PATH}/cargo-asm ${BIN_PATH}/cargo-asm
COPY --link --from=cargo-binutils \
    ${BIN_PATH}/cargo-* \
    ${BIN_PATH}/rust-* \
    ${BIN_PATH}/
COPY --link --from=cargo-bloat ${BIN_PATH}/cargo-bloat ${BIN_PATH}/cargo-bloat
COPY --link --from=cargo-check ${BIN_PATH}/cargo-check ${BIN_PATH}/cargo-check
COPY --link --from=cargo-edit \
    ${BIN_PATH}/cargo-add \
    ${BIN_PATH}/cargo-rm \
    ${BIN_PATH}/cargo-set-version \
    ${BIN_PATH}/cargo-upgrade \
    ${BIN_PATH}/
COPY --link --from=cargo-expand ${BIN_PATH}/cargo-expand ${BIN_PATH}/cargo-expand
COPY --link --from=cargo-fix ${BIN_PATH}/cargo-fix ${BIN_PATH}/cargo-fix
COPY --link --from=cargo-machete ${BIN_PATH}/cargo-machete ${BIN_PATH}/cargo-machete
COPY --link --from=cargo-tree ${BIN_PATH}/cargo-tree ${BIN_PATH}/cargo-tree
COPY --link --from=cargo-watch ${BIN_PATH}/cargo-watch ${BIN_PATH}/cargo-watch
COPY --link --from=ast-grep ${BIN_PATH}/sg ${BIN_PATH}/sg
COPY --link --from=atuin ${BIN_PATH}/atuin ${BIN_PATH}/atuin
COPY --link --from=bandwhich ${BIN_PATH}/bandwhich ${BIN_PATH}/bandwhich
COPY --link --from=bat ${BIN_PATH}/bat ${BIN_PATH}/bat
COPY --link --from=bottom ${BIN_PATH}/btm ${BIN_PATH}/btm
COPY --link --from=broot ${BIN_PATH}/broot ${BIN_PATH}/broot
COPY --link --from=cpz ${BIN_PATH}/cpz ${BIN_PATH}/cpz
COPY --link --from=delta ${BIN_PATH}/delta ${BIN_PATH}/delta
COPY --link --from=deno ${BIN_PATH}/deno ${BIN_PATH}/deno
COPY --link --from=dutree ${BIN_PATH}/dutree ${BIN_PATH}/dutree
COPY --link --from=erdtree ${BIN_PATH}/erd ${BIN_PATH}/erd
COPY --link --from=eza ${BIN_PATH}/eza ${BIN_PATH}/eza
COPY --link --from=fd ${BIN_PATH}/fd ${BIN_PATH}/fd
COPY --link --from=frawk ${BIN_PATH}/frawk ${BIN_PATH}/frawk
COPY --link --from=gping ${BIN_PATH}/gping ${BIN_PATH}/gping
COPY --link --from=helix ${BIN_PATH}/hx ${BIN_PATH}/hx
COPY --link --from=herdr ${BIN_PATH}/herdr ${BIN_PATH}/herdr
COPY --link --from=hx-lsp ${BIN_PATH}/hx-lsp ${BIN_PATH}/hx-lsp
COPY --link --from=hyperfine ${BIN_PATH}/hyperfine ${BIN_PATH}/hyperfine
COPY --link --from=leaf ${BIN_PATH}/leaf ${BIN_PATH}/leaf
COPY --link --from=lsd ${BIN_PATH}/lsd ${BIN_PATH}/lsd
COPY --link --from=lsp-ai ${BIN_PATH}/lsp-ai ${BIN_PATH}/lsp-ai
COPY --link --from=nushell ${BIN_PATH}/nu ${BIN_PATH}/nu
COPY --link --from=pay-respects ${BIN_PATH}/pay-respects ${BIN_PATH}/pay-respects
COPY --link --from=prek ${BIN_PATH}/prek ${BIN_PATH}/prek
COPY --link --from=prmt ${BIN_PATH}/prmt ${BIN_PATH}/prmt
COPY --link --from=procs ${BIN_PATH}/procs ${BIN_PATH}/procs
COPY --link --from=rg ${BIN_PATH}/rg ${BIN_PATH}/rg
COPY --link --from=rga ${BIN_PATH}/rga ${BIN_PATH}/rga
COPY --link --from=rmz ${BIN_PATH}/rmz ${BIN_PATH}/rmz
COPY --link --from=rtk ${BIN_PATH}/rtk ${BIN_PATH}/rtk
COPY --link --from=sad ${BIN_PATH}/sad ${BIN_PATH}/sad
COPY --link --from=sd ${BIN_PATH}/sd ${BIN_PATH}/sd
COPY --link --from=sheldon ${BIN_PATH}/sheldon ${BIN_PATH}/sheldon
COPY --link --from=shellharden ${BIN_PATH}/shellharden ${BIN_PATH}/shellharden
COPY --link --from=starship ${BIN_PATH}/starship ${BIN_PATH}/starship
COPY --link --from=stylua ${BIN_PATH}/stylua ${BIN_PATH}/stylua
COPY --link --from=tokei ${BIN_PATH}/tokei ${BIN_PATH}/tokei
COPY --link --from=t-rec ${BIN_PATH}/t-rec ${BIN_PATH}/t-rec
COPY --link --from=tree-sitter ${BIN_PATH}/tree-sitter ${BIN_PATH}/tree-sitter
COPY --link --from=typos-lsp ${BIN_PATH}/typos-lsp ${BIN_PATH}/typos-lsp
COPY --link --from=watchexec ${BIN_PATH}/watchexec ${BIN_PATH}/watchexec
COPY --link --from=xh ${BIN_PATH}/xh ${BIN_PATH}/xh
COPY --link --from=zoxide ${BIN_PATH}/zoxide ${BIN_PATH}/zoxide
COPY --link --from=zsh-patina ${BIN_PATH}/zsh-patina ${BIN_PATH}/zsh-patina
COPY --link --from=helix ${HELIX_DEFAULT_RUNTIME} ${HELIX_DEFAULT_RUNTIME}
