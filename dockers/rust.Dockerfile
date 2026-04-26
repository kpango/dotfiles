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

RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
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
    && curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash

FROM kpango/rust:nightly AS old

FROM rust-base AS rust-stable
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked rustup update stable && rustup default stable

FROM rust-base AS ast-grep
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    ast-grep

FROM rust-base AS bandwhich
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    bandwhich

FROM rust-stable AS bat
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    bat

FROM rust-stable AS bottom
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    bottom

FROM rust-base AS broot
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    broot

FROM rust-base AS cargo-asm
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-asm

FROM rust-base AS cargo-binutils
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install --git https://github.com/japaric/cargo-binutils

FROM rust-base AS cargo-bloat
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git https://github.com/RazrFalcon/cargo-bloat

FROM rust-base AS cargo-check
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-check

FROM rust-base AS cargo-edit
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-edit

FROM rust-base AS cargo-expand
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-expand

FROM rust-base AS cargo-fix
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    cargo-fix

FROM rust-base AS cargo-machete
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    cargo-machete

FROM rust-base AS cargo-tree
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-tree

FROM rust-base AS cargo-watch
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y cargo-watch

FROM rust-base AS delta
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    git-delta

FROM rust-base AS deno
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN RUST_BACKTRACE=full cargo binstall -y \
    deno

FROM rust-base AS dog
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git https://github.com/ogham/dog dog

FROM rust-base AS dutree
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    dutree

FROM rust-base AS erdtree
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    erdtree

FROM rust-stable AS eza
# RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    eza

FROM rust-base AS fd
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git https://github.com/sharkdp/fd

FROM rust-base AS frawk
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -y \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends --fix-missing \
    libllvm22 \
    llvm-22 \
    llvm-22-dev \
    && rm -rf /var/lib/apt/lists/*
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --features use_jemalloc,allow_avx2,unstable \
    --git https://github.com/ezrosent/frawk frawk

FROM rust-stable AS gping
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    gping

FROM rust-base AS helix
ENV HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime
RUN git clone --depth 1 https://github.com/helix-editor/helix \
    && cd helix \
    && RUST_BACKTRACE=full \
    HELIX_DEFAULT_RUNTIME=${HELIX_DEFAULT_RUNTIME} \
    cargo +nightly install \
    --profile opt \
    --path helix-term \
    --locked \
    && mkdir -p ${HELIX_DEFAULT_RUNTIME} \
    && cp -r ./runtime ${HELIX_DEFAULT_RUNTIME}

FROM rust-base AS herdr
RUN case "$(uname -m)" in \
    aarch64) ARCH=aarch64 ;; \
    x86_64) ARCH=x86_64 ;; \
    *) echo "Unsupported architecture: $(uname -m)" && exit 1 ;; \
  esac && \
  HERDR_VERSION=$(curl -s https://api.github.com/repos/ogulcancelik/herdr/releases/latest | jq -r .tag_name | sed 's/^v//') && \
  curl -L -o herdr "https://github.com/ogulcancelik/herdr/releases/download/${HERDR_VERSION}/herdr-linux-${ARCH}" && \
  chmod +x herdr && \
  mv herdr "${BIN_PATH}/herdr"

FROM rust-base AS hyperfine
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    hyperfine

FROM rust-base AS lsd
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git https://github.com/lsd-rs/lsd --branch main

FROM rust-base AS lsp-ai
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN case "$(uname -m)" in \
    aarch64) ARCH=aarch64 ;; \
    x86_64) ARCH=x86_64 ;; \
    *) echo "Unsupported architecture: $(uname -m)" && exit 1 ;; \
  esac && \
  LSP_AI_VERSION=$(curl -s https://api.github.com/repos/SilasMarvin/lsp-ai/releases/latest | jq -r .tag_name | sed 's/^v//') && \
  curl -L -o lsp-ai.gz "https://github.com/SilasMarvin/lsp-ai/releases/download/v${LSP_AI_VERSION}/lsp-ai-${ARCH}-unknown-linux-gnu.gz" && \
  gzip -d lsp-ai.gz && \
  chmod +x lsp-ai && \
  mv lsp-ai "${BIN_PATH}/lsp-ai"

FROM rust-base AS nushell
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y nu

FROM rust-base AS prek
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    prek

FROM rust-base AS procs
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly install \
    --git https://github.com/dalance/procs

FROM rust-stable AS rg
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    ripgrep

FROM rg AS rga
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y \
    ripgrep_all

FROM rust-base AS nixpkgs-fmt
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y nixpkgs-fmt

FROM rust-base AS rnix-lsp
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git https://github.com/nix-community/rnix-lsp

FROM rust-base AS rtk
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git https://github.com/rtk-ai/rtk

FROM rust-base AS sad
RUN git clone --depth 1 https://github.com/ms-jpq/sad \
    && cd sad \
    && cargo install --path .

FROM rust-base AS sd
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    sd

FROM rust-base AS shellharden
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    shellharden

FROM rust-base AS sheldon
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install \
    --git https://github.com/rossmacarthur/sheldon

FROM rust-base AS starship
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y starship

FROM rust-base AS stylua
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y stylua

FROM rust-base AS t-rec
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    t-rec

FROM rust-base AS tokei
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly install \
    --git https://github.com/XAMPPRocky/tokei \
    tokei

FROM rust-base AS tree-sitter
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
    tree-sitter-cli

FROM rust-stable AS watchexec
# hadolint ignore=DL3003,DL4006,SC2086,SC2153,SC2098,SC2016,SC2046,DL3008,DL3047
RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo binstall -y watchexec-cli

FROM rust-base AS xh
# RUN --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked --mount=type=cache,target=${CARGO_HOME}/git,sharing=locked --mount=type=secret,id=gat GITHUB_TOKEN=$(cat /run/secrets/gat) cargo +nightly binstall -y \
RUN RUSTFLAGS="--cfg reqwest_unstable" \
    cargo +nightly binstall -y \
    xh

FROM scratch AS rust-pre
ENV HOME=/root
ENV RUST_HOME=/usr/local/lib/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV RUSTUP_HOME=${RUST_HOME}/rustup
ENV BIN_PATH=${CARGO_HOME}/bin

COPY --link --from=rust-base ${CARGO_HOME} ${CARGO_HOME}
COPY --link --from=rust-base ${RUSTUP_HOME}/settings.toml ${RUSTUP_HOME}/settings.toml
COPY --link --from=rust-base ${RUSTUP_HOME}/toolchains ${RUSTUP_HOME}/toolchains
# COPY --link --from=frawk ${BIN_PATH}/frawk ${BIN_PATH}/frawk
COPY --link --from=nushell ${BIN_PATH}/nu ${BIN_PATH}/nu
COPY --link --from=ast-grep ${BIN_PATH}/sg ${BIN_PATH}/sg
COPY --link --from=deno ${BIN_PATH}/deno ${BIN_PATH}/deno
COPY --link --from=watchexec ${BIN_PATH}/watchexec ${BIN_PATH}/watchexec
COPY --link --from=bandwhich ${BIN_PATH}/bandwhich ${BIN_PATH}/bandwhich
COPY --link --from=bat ${BIN_PATH}/bat ${BIN_PATH}/bat
COPY --link --from=bottom ${BIN_PATH}/btm ${BIN_PATH}/btm
COPY --link --from=broot ${BIN_PATH}/broot ${BIN_PATH}/broot
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
COPY --link --from=delta ${BIN_PATH}/delta ${BIN_PATH}/delta
COPY --link --from=dog ${BIN_PATH}/dog ${BIN_PATH}/dog
COPY --link --from=dutree ${BIN_PATH}/dutree ${BIN_PATH}/dutree
COPY --link --from=erdtree ${BIN_PATH}/erd ${BIN_PATH}/erd
COPY --link --from=eza ${BIN_PATH}/eza ${BIN_PATH}/eza
COPY --link --from=fd ${BIN_PATH}/fd ${BIN_PATH}/fd
COPY --link --from=gping ${BIN_PATH}/gping ${BIN_PATH}/gping
COPY --link --from=helix ${BIN_PATH}/hx ${BIN_PATH}/hx
COPY --link --from=herdr ${BIN_PATH}/herdr ${BIN_PATH}/herdr
COPY --link --from=hyperfine ${BIN_PATH}/hyperfine ${BIN_PATH}/hyperfine
COPY --link --from=lsd ${BIN_PATH}/lsd ${BIN_PATH}/lsd
COPY --link --from=lsp-ai ${BIN_PATH}/lsp-ai ${BIN_PATH}/lsp-ai
COPY --link --from=prek ${BIN_PATH}/prek ${BIN_PATH}/prek
COPY --link --from=procs ${BIN_PATH}/procs ${BIN_PATH}/procs
COPY --link --from=rg ${BIN_PATH}/rg ${BIN_PATH}/rg
COPY --link --from=rga ${BIN_PATH}/rga ${BIN_PATH}/rga
COPY --link --from=nixpkgs-fmt ${BIN_PATH}/nixpkgs-fmt ${BIN_PATH}/nixpkgs-fmt
COPY --link --from=rnix-lsp ${BIN_PATH}/rnix-lsp ${BIN_PATH}/rnix-lsp
COPY --link --from=rtk ${BIN_PATH}/rtk ${BIN_PATH}/rtk
COPY --link --from=sad ${BIN_PATH}/sad ${BIN_PATH}/sad
COPY --link --from=sd ${BIN_PATH}/sd ${BIN_PATH}/sd
COPY --link --from=sheldon ${BIN_PATH}/sheldon ${BIN_PATH}/sheldon
COPY --link --from=shellharden ${BIN_PATH}/shellharden ${BIN_PATH}/shellharden
COPY --link --from=starship ${BIN_PATH}/starship ${BIN_PATH}/starship
COPY --link --from=stylua ${BIN_PATH}/stylua ${BIN_PATH}/stylua
COPY --link --from=t-rec ${BIN_PATH}/t-rec ${BIN_PATH}/t-rec
COPY --link --from=tokei ${BIN_PATH}/tokei ${BIN_PATH}/tokei
COPY --link --from=tree-sitter ${BIN_PATH}/tree-sitter ${BIN_PATH}/tree-sitter
COPY --link --from=xh ${BIN_PATH}/xh ${BIN_PATH}/xh

FROM rust-base AS rust-compress
ENV RUST_HOME=/usr/local/lib/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV BIN_PATH=${CARGO_HOME}/bin
COPY --link --from=rust-pre ${BIN_PATH}/ ${BIN_PATH}/
RUN find ${BIN_PATH} -type f -executable | xargs -P $(nproc) -n 1 upx -9

FROM scratch AS rust
ENV RUST_HOME=/usr/local/lib/rust
ENV CARGO_HOME=${RUST_HOME}/cargo
ENV RUSTUP_HOME=${RUST_HOME}/rustup
ENV BIN_PATH=${CARGO_HOME}/bin
ENV HELIX_DEFAULT_RUNTIME=/usr/lib/helix/runtime

COPY --link --from=rust-compress ${BIN_PATH}/ ${BIN_PATH}/
COPY --link --from=rust-pre ${RUSTUP_HOME} ${RUSTUP_HOME}
COPY --link --from=helix ${HELIX_DEFAULT_RUNTIME} ${HELIX_DEFAULT_RUNTIME}
