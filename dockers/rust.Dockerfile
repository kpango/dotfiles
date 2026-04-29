# syntax = docker/dockerfile:latest
FROM kpango/base:nightly AS rust-base

ARG TOOLCHAIN=nightly

ENV HOME=/root
ENV RUST_HOME=/usr/local/lib/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV RUSTUP_HOME=${RUST_HOME}/rustup
ENV BIN_PATH=${CARGO_HOME}/bin
ENV PATH=${BIN_PATH}:${PATH}
ENV CARGO_BUILD_JOBS=2
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

RUN curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs \
    | CARGO_HOME=${CARGO_HOME} RUSTUP_HOME=${RUSTUP_HOME} sh -s -- --default-toolchain nightly -y \
    && CARGO_HOME=${CARGO_HOME} RUSTUP_HOME=${RUSTUP_HOME} ${CARGO_HOME}/bin/rustup install stable beta \
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

FROM kpango/rust:nightly AS old

FROM rust-base AS rust-stable
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked rustup update stable && rustup default stable

FROM rust-base AS cargo-asm
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-asm \
    && upx -9 ${BIN_PATH}/cargo-asm || true

FROM rust-base AS cargo-binutils
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-binutils \
    && upx -9 ${BIN_PATH}/cargo-* ${BIN_PATH}/rust-* || true

FROM rust-base AS cargo-bloat
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-bloat \
    && upx -9 ${BIN_PATH}/cargo-bloat || true

FROM rust-base AS cargo-check
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-check \
    && upx -9 ${BIN_PATH}/cargo-check || true

FROM rust-base AS cargo-edit
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-edit \
    && upx -9 ${BIN_PATH}/cargo-add ${BIN_PATH}/cargo-rm ${BIN_PATH}/cargo-set-version ${BIN_PATH}/cargo-upgrade || true

FROM rust-base AS cargo-expand
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-expand \
    && upx -9 ${BIN_PATH}/cargo-expand || true

FROM rust-base AS cargo-fix
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    cargo-fix \
    && upx -9 ${BIN_PATH}/cargo-fix || true

FROM rust-base AS cargo-machete
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    cargo-machete \
    && upx -9 ${BIN_PATH}/cargo-machete || true

FROM rust-base AS cargo-tree
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-tree \
    && upx -9 ${BIN_PATH}/cargo-tree || true

FROM rust-base AS cargo-watch
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-watch \
    && upx -9 ${BIN_PATH}/cargo-watch || true

FROM rust-base AS ast-grep
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    ast-grep \
    && upx -9 ${BIN_PATH}/sg || true

FROM rust-stable AS atuin
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    atuin \
    && upx -9 ${BIN_PATH}/atuin || true

FROM rust-base AS bandwhich
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    bandwhich \
    && upx -9 ${BIN_PATH}/bandwhich || true

FROM rust-stable AS bat
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    bat \
    && upx -9 ${BIN_PATH}/bat || true

FROM rust-stable AS bottom
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    bottom \
    && upx -9 ${BIN_PATH}/btm || true

FROM rust-base AS broot
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    broot \
    && upx -9 ${BIN_PATH}/broot || true

FROM rust-stable AS cpz
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    cpz \
    && upx -9 ${BIN_PATH}/cpz || true

FROM rust-base AS delta
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    git-delta \
    && upx -9 ${BIN_PATH}/delta || true

FROM rust-stable AS deno
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y deno \
    && upx -9 ${BIN_PATH}/deno || true

FROM rust-base AS dog
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git ${GITHUB}/ogham/dog dog \
    && upx -9 ${BIN_PATH}/dog || true

FROM rust-base AS dutree
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    dutree \
    && upx -9 ${BIN_PATH}/dutree || true

FROM rust-base AS erdtree
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    erdtree \
    && upx -9 ${BIN_PATH}/erd || true

FROM rust-stable AS eza
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    eza \
    && upx -9 ${BIN_PATH}/eza || true

FROM rust-base AS fd
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y fd-find \
    && upx -9 ${BIN_PATH}/fd || true

FROM rust-base AS frawk
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --no-default-features --features use_jemalloc,allow_avx2 \
    --git ${GITHUB}/ezrosent/frawk frawk \
    && upx -9 ${BIN_PATH}/frawk || true

FROM rust-stable AS gping
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    gping \
    && upx -9 ${BIN_PATH}/gping || true

FROM rust-base AS helix
ENV HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime
RUN git clone --depth 1 ${GITHUB}/helix-editor/helix \
    && cd helix \
    && RUST_BACKTRACE=full \
    HELIX_DEFAULT_RUNTIME=${HELIX_DEFAULT_RUNTIME} \
    cargo +nightly install \
    --profile opt \
    --path helix-term \
    --locked \
    && mkdir -p ${HELIX_DEFAULT_RUNTIME} \
    && cp -r ./runtime ${HELIX_DEFAULT_RUNTIME} \
    && upx -9 ${BIN_PATH}/hx || true

FROM rust-base AS herdr
RUN --mount=type=secret,id=gat case "$(uname -m)" in \
    aarch64) ARCH=aarch64 ;; \
    x86_64) ARCH=x86_64 ;; \
    *) echo "Unsupported architecture: $(uname -m)" && exit 1 ;; \
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
  && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-linux-${ARCH}" \
  && echo ${URL} \
  && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo ${BIN_NAME} "${URL}" \
  && chmod +x ${BIN_NAME} \
  && mv ${BIN_NAME} "${BIN_PATH}/${BIN_NAME}" \
  && upx -9 ${BIN_PATH}/herdr || true

FROM rust-base AS hx-lsp
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    hx-lsp \
    && upx -9 ${BIN_PATH}/hx-lsp || true

FROM rust-base AS hyperfine
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    hyperfine \
    && upx -9 ${BIN_PATH}/hyperfine || true

FROM rust-base AS lsd
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y lsd \
    && upx -9 ${BIN_PATH}/lsd || true

FROM rust-base AS lsp-ai
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=secret,id=gat case "$(uname -m)" in \
    aarch64) ARCH=aarch64 ;; \
    x86_64) ARCH=x86_64 ;; \
    *) echo "Unsupported architecture: $(uname -m)" && exit 1 ;; \
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
  && URL="${GITHUB}/${REPO}/${RELEASE_DL}/v${VERSION}/${BIN_NAME}-${ARCH}-unknown-linux-gnu.gz" \
  && echo ${URL} \
  && curl --retry ${CURL_RETRY} --retry-all-errors --retry-delay ${CURL_RETRY_DELAY} -fsSLo ${BIN_NAME}.gz "${URL}" \
  && gzip -d ${BIN_NAME}.gz \
  && chmod +x ${BIN_NAME} \
  && mv ${BIN_NAME} "${BIN_PATH}/${BIN_NAME}" \
  && upx -9 ${BIN_PATH}/lsp-ai || true

FROM rust-base AS nixpkgs-fmt
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y nixpkgs-fmt \
    && upx -9 ${BIN_PATH}/nixpkgs-fmt || true

FROM rust-base AS nushell
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y nu \
    && upx -9 ${BIN_PATH}/nu || true

FROM rust-stable AS pay-respects
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    pay-respects \
    && upx -9 ${BIN_PATH}/pay-respects || true

FROM rust-base AS prek
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    prek \
    && upx -9 ${BIN_PATH}/prek || true

FROM rust-base AS procs
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y procs \
    && upx -9 ${BIN_PATH}/procs || true

FROM rust-stable AS rg
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    ripgrep \
    && upx -9 ${BIN_PATH}/rg || true

FROM rg AS rga
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    ripgrep_all \
    && upx -9 ${BIN_PATH}/rga || true

FROM rust-stable AS rmz
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    rmz \
    && upx -9 ${BIN_PATH}/rmz || true

FROM rust-base AS rnix-lsp
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git ${GITHUB}/nix-community/rnix-lsp \
    && upx -9 ${BIN_PATH}/rnix-lsp || true

FROM rust-base AS rtk
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git ${GITHUB}/rtk-ai/rtk \
    && upx -9 ${BIN_PATH}/rtk || true

FROM rust-base AS sad
RUN git clone --depth 1 ${GITHUB}/ms-jpq/sad \
    && cd sad \
    && cargo install --path . \
    && upx -9 ${BIN_PATH}/sad || true

FROM rust-base AS sd
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    sd \
    && upx -9 ${BIN_PATH}/sd || true

FROM rust-base AS sheldon
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y sheldon \
    && upx -9 ${BIN_PATH}/sheldon || true

FROM rust-base AS shellharden
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    shellharden \
    && upx -9 ${BIN_PATH}/shellharden || true

FROM rust-base AS starship
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y starship \
    && upx -9 ${BIN_PATH}/starship || true

FROM rust-base AS stylua
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y stylua \
    && upx -9 ${BIN_PATH}/stylua || true

FROM rust-base AS tokei
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y tokei \
    && upx -9 ${BIN_PATH}/tokei || true

FROM rust-base AS t-rec
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    t-rec \
    && upx -9 ${BIN_PATH}/t-rec || true

FROM rust-base AS tree-sitter
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    tree-sitter-cli \
    && upx -9 ${BIN_PATH}/tree-sitter || true

FROM rust-base AS typos-lsp
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly install \
    --git ${GITHUB}/tekumara/typos-lsp --locked typos-lsp \
    && upx -9 ${BIN_PATH}/typos-lsp || true

FROM rust-stable AS watchexec
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y watchexec-cli \
    && upx -9 ${BIN_PATH}/watchexec || true

FROM rust-base AS xh
RUN RUSTFLAGS="--cfg reqwest_unstable" \
    cargo +nightly binstall -y \
    xh \
    && upx -9 ${BIN_PATH}/xh || true

FROM rust-stable AS zoxide
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    zoxide \
    && upx -9 ${BIN_PATH}/zoxide || true

FROM rust-stable AS zsh-patina
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    zsh-patina \
    && upx -9 ${BIN_PATH}/zsh-patina || true

FROM scratch AS rust-pre
ENV HOME=/root
ENV RUST_HOME=/usr/local/lib/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV RUSTUP_HOME=${RUST_HOME}/rustup
ENV BIN_PATH=${CARGO_HOME}/bin

COPY --link --from=rust-base ${CARGO_HOME} ${CARGO_HOME}
COPY --link --from=rust-base ${RUSTUP_HOME}/settings.toml ${RUSTUP_HOME}/settings.toml
COPY --link --from=rust-base ${RUSTUP_HOME}/toolchains ${RUSTUP_HOME}/toolchains
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
COPY --link --from=dog ${BIN_PATH}/dog ${BIN_PATH}/dog
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
COPY --link --from=lsd ${BIN_PATH}/lsd ${BIN_PATH}/lsd
COPY --link --from=lsp-ai ${BIN_PATH}/lsp-ai ${BIN_PATH}/lsp-ai
COPY --link --from=nixpkgs-fmt ${BIN_PATH}/nixpkgs-fmt ${BIN_PATH}/nixpkgs-fmt
COPY --link --from=nushell ${BIN_PATH}/nu ${BIN_PATH}/nu
COPY --link --from=pay-respects ${BIN_PATH}/pay-respects ${BIN_PATH}/pay-respects
COPY --link --from=prek ${BIN_PATH}/prek ${BIN_PATH}/prek
COPY --link --from=procs ${BIN_PATH}/procs ${BIN_PATH}/procs
COPY --link --from=rg ${BIN_PATH}/rg ${BIN_PATH}/rg
COPY --link --from=rga ${BIN_PATH}/rga ${BIN_PATH}/rga
COPY --link --from=rmz ${BIN_PATH}/rmz ${BIN_PATH}/rmz
COPY --link --from=rnix-lsp ${BIN_PATH}/rnix-lsp ${BIN_PATH}/rnix-lsp
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

FROM scratch AS rust
ENV RUST_HOME=/usr/local/lib/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV RUSTUP_HOME=${RUST_HOME}/rustup
ENV BIN_PATH=${CARGO_HOME}/bin
ENV HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime

COPY --link --from=rust-pre ${BIN_PATH}/ ${BIN_PATH}/
COPY --link --from=rust-pre ${RUSTUP_HOME} ${RUSTUP_HOME}
COPY --link --from=helix ${HELIX_DEFAULT_RUNTIME} ${HELIX_DEFAULT_RUNTIME}
