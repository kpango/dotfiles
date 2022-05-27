FROM kpango/dev-base:latest AS rust-base

ARG TOOLCHAIN=nightly

ENV HOME /root
ENV RUSTUP ${HOME}/.rustup
ENV CARGO ${HOME}/.cargo
ENV BIN_PATH ${CARGO}/bin
ENV PATH ${BIN_PATH}:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN rustup install stable \
    && rustup install beta \
    && rustup install nightly \
    && rustup toolchain install nightly \
    && rustup default nightly \
    && rustup update \
    && rustup component add \
       rustfmt \
       rust-analysis \
       rust-src \
       clippy \
       --toolchain nightly

# RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache

FROM rust-base AS rnix-lsp
RUN cargo install --force --no-default-features \
    --git https://github.com/nix-community/rnix-lsp

# FROM rust-base AS nushell
# RUN cargo install --force --features=extra \
#     --git https://github.com/nushell/nushell nu

FROM rust-base AS cargo-bloat
RUN cargo install --force --no-default-features \
    --git https://github.com/RazrFalcon/cargo-bloat

FROM rust-base AS fd
RUN cargo install --force --no-default-features \
    --git https://github.com/sharkdp/fd

FROM rust-base AS starship
RUN rustup update stable \
    && rustup default stable \
    && cargo install --force --no-default-features \
    starship

FROM rust-base AS exa
RUN cargo +nightly install --force --no-default-features \
# RUN rustup update stable \
#     && rustup default stable \
#     && cargo install --force --no-default-features \
#     exa

# FROM rust-base AS bandwhich
# RUN cargo +nightly install --force --no-default-features \
#     bandwhich

# FROM rust-base AS shellharden
# RUN cargo +nightly install --force --no-default-features \
#     shellharden

FROM rust-base AS rg
RUN rustup update stable \
    && rustup default stable \
    && RUSTFLAGS="-C target-cpu=native" \
    RUSTC_BOOTSTRAP=1 \
    cargo install --force --features 'pcre2 simd-accel' \
    ripgrep
    # cargo +nightly install --force --features 'pcre2 simd-accel' \
    # ripgrep

FROM rust-base AS rga
COPY --from=rg ${BIN_PATH}/rg ${BIN_PATH}/rg
RUN cargo install --locked --force --no-default-features \
    ripgrep_all

FROM rust-base AS procs
RUN cargo install --force --no-default-features \
    --git https://github.com/dalance/procs

# FROM kpango/rust:latest AS bat
FROM rust-base AS bat
# RUN cargo install --locked --force --no-default-features \
    # bat
RUN rustup update stable \
    && rustup default stable \
    && cargo install --force --locked \
    bat

FROM rust-base AS dutree
RUN cargo +nightly install --force --no-default-features \
    dutree

FROM rust-base AS broot
RUN cargo +nightly install --force --no-default-features \
    broot

FROM rust-base AS dog
RUN cargo install --force --no-default-features \
    --git https://github.com/ogham/dog dog

FROM rust-base AS hyperfine
RUN cargo +nightly install --force --no-default-features \
    hyperfine

FROM rust-base AS sd
RUN cargo +nightly install --force --no-default-features \
    sd

FROM rust-base AS gping
# RUN cargo +nightly install --force --no-default-features \
#     gping
RUN rustup update stable \
    && rustup default stable \
    && cargo install --force --no-default-features \
    gping



FROM rust-base AS sad
RUN git clone --depth 1 https://github.com/ms-jpq/sad \
    && cd sad \
    && cargo install --force --locked --all-features --path .

FROM rust-base AS lsd
RUN cargo install --force --no-default-features \
    --git https://github.com/Peltoche/lsd --branch master

FROM rust-base AS delta
RUN cargo +nightly install --force --no-default-features \
    git-delta

FROM rust-base AS bottom
RUN rustup update stable \
    && rustup default stable \
    && cargo install --force --no-default-features \
    --git https://github.com/ClementTsang/bottom

FROM rust-base AS tokei
RUN cargo +nightly install --force --no-default-features \
    tokei

FROM rust-base AS rustfix
RUN cargo +nightly install --force --no-default-features \
    rustfix

FROM rust-base AS watchexec
RUN cargo +nightly install --force --no-default-features \
    watchexec-cli

FROM rust-base AS xh
RUN cargo +nightly install --force --no-default-features \
    xh

# FROM rust-base AS frawk
# RUN cargo install --locked --force \
#     --features use_jemalloc,allow_avx2,unstable \
#     --git https://github.com/ezrosent/frawk frawk

# FROM rust-base AS racer
# RUN cargo +nightly install --force  \
#     racer

# FROM watchexec AS cargo-watch
# RUN cargo +nightly install --force --no-default-features \
#     cargo-watch
# RUN cargo install cargo-watch

FROM rust-base AS cargo-tree
RUN cargo install cargo-tree

FROM rust-base AS cargo-asm
RUN cargo install cargo-asm

FROM rust-base AS cargo-expand
RUN cargo install cargo-expand

FROM rust-base AS cargo-binutils
RUN cargo install --git https://github.com/japaric/cargo-binutils

# FROM rust-base AS cargo-src
# RUN cargo install --force --no-default-features \
#     --verbose \
#     --git https://github.com/rust-dev-tools/cargo-src --branch master

FROM rust-base AS cargo-check
RUN cargo install cargo-check

FROM scratch AS rust
ENV HOME /root
ENV RUSTUP ${HOME}/.rustup
ENV CARGO ${HOME}/.cargo
ENV BIN_PATH ${CARGO}/bin

# COPY --from=cargo-src ${BIN_PATH}/cargo-src ${BIN_PATH}/cargo-src
# COPY --from=racer ${BIN_PATH}/racer ${BIN_PATH}/racer
# COPY --from=frawk ${BIN_PATH}/frawk ${BIN_PATH}/frawk
# COPY --from=bandwhich ${BIN_PATH}/bandwhich ${BIN_PATH}/bandwhich
COPY --from=bat ${BIN_PATH}/bat ${BIN_PATH}/bat
COPY --from=bottom ${BIN_PATH}/btm ${BIN_PATH}/btm
COPY --from=broot ${BIN_PATH}/broot ${BIN_PATH}/broot
COPY --from=cargo-asm ${BIN_PATH}/cargo-asm ${BIN_PATH}/cargo-asm
COPY --from=cargo-binutils ${BIN_PATH}/cargo-* ${BIN_PATH}/
COPY --from=cargo-binutils ${BIN_PATH}/rust-* ${BIN_PATH}/
COPY --from=cargo-check ${BIN_PATH}/cargo-check ${BIN_PATH}/cargo-check
COPY --from=cargo-expand ${BIN_PATH}/cargo-expand ${BIN_PATH}/cargo-expand
COPY --from=cargo-tree ${BIN_PATH}/cargo-tree ${BIN_PATH}/cargo-tree
# COPY --from=cargo-watch ${BIN_PATH}/cargo-watch ${BIN_PATH}/cargo-watch
COPY --from=delta ${BIN_PATH}/delta ${BIN_PATH}/delta
COPY --from=dog ${BIN_PATH}/dog ${BIN_PATH}/dog
COPY --from=dutree ${BIN_PATH}/dutree ${BIN_PATH}/dutree
COPY --from=exa ${BIN_PATH}/exa ${BIN_PATH}/exa
COPY --from=fd ${BIN_PATH}/fd ${BIN_PATH}/fd
COPY --from=gping ${BIN_PATH}/gping ${BIN_PATH}/gping
COPY --from=hyperfine ${BIN_PATH}/hyperfine ${BIN_PATH}/hyperfine
COPY --from=lsd ${BIN_PATH}/lsd ${BIN_PATH}/lsd
# COPY --from=nushell ${BIN_PATH}/nu ${BIN_PATH}/nu
COPY --from=procs ${BIN_PATH}/procs ${BIN_PATH}/procs
COPY --from=rg ${BIN_PATH}/rg ${BIN_PATH}/rg
COPY --from=rga ${BIN_PATH}/rga ${BIN_PATH}/rga
COPY --from=rnix-lsp ${BIN_PATH}/rnix-lsp ${BIN_PATH}/rnix-lsp
COPY --from=rust-base ${BIN_PATH}/rustc ${BIN_PATH}/rustc
COPY --from=rust-base ${BIN_PATH}/rustup ${BIN_PATH}/rustup
COPY --from=rust-base ${CARGO} ${CARGO}
COPY --from=rust-base ${RUSTUP}/settings.toml ${RUSTUP}/settings.toml
COPY --from=rust-base ${RUSTUP}/toolchains ${RUSTUP}/toolchains
COPY --from=sad ${BIN_PATH}/sad ${BIN_PATH}/sad
COPY --from=sd ${BIN_PATH}/sd ${BIN_PATH}/sd
# COPY --from=shellharden ${BIN_PATH}/shellharden ${BIN_PATH}/shellharden
COPY --from=starship ${BIN_PATH}/starship ${BIN_PATH}/starship
COPY --from=tokei ${BIN_PATH}/tokei ${BIN_PATH}/tokei
COPY --from=watchexec ${BIN_PATH}/watchexec ${BIN_PATH}/watchexec
COPY --from=xh ${BIN_PATH}/xh ${BIN_PATH}/xh
