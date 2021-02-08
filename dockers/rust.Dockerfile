FROM kpango/dev-base:latest AS rust-base

ARG TOOLCHAIN=nightly

ENV PATH /root/.cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN rustup install stable \
    && rustup install beta \
    && rustup install nightly \
    && rustup toolchain install nightly \
    && rustup default nightly \
    && rustup update \
    && rustup component add \
       rustfmt \
       rls \
       rust-analysis \
       rust-src \
       clippy \
       --toolchain nightly 

RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache

# FROM rust-base AS nix-lsp
# RUN cargo install --force --no-default-features \
#     --git https://gitlab.com/jD91mZM2/nix-lsp

FROM rust-base AS cargo-bloat
RUN cargo install --force --no-default-features \
    --git https://github.com/RazrFalcon/cargo-bloat

FROM rust-base AS fd
RUN cargo install --force --no-default-features \
    --git https://github.com/sharkdp/fd
# 
# FROM rust-base AS starship
# RUN cargo install --force --no-default-features \
#     --git https://github.com/starship/starship

FROM rust-base AS exa
RUN cargo +nightly install --force \
    exa

FROM rust-base AS rg
RUN cargo +nightly install --force --no-default-features \
    ripgrep

FROM rust-base AS procs
RUN cargo install --force --no-default-features \
    --git https://github.com/dalance/procs

FROM rust-base AS bat
RUN cargo install --force --locked \
    --git https://github.com/sharkdp/bat

FROM rust-base AS dutree
RUN cargo +nightly install --force --no-default-features \
    dutree

FROM rust-base AS hyperfine
RUN cargo +nightly install --force --no-default-features \
    hyperfine

FROM rust-base AS sd
RUN cargo +nightly install --force --no-default-features \
    sd

FROM rust-base AS gping
RUN cargo +nightly install --force --no-default-features \
    gping

# FROM rust-base AS sad
# RUN rustup update stable \
#     && rustup default stable \
#     && cargo install --force --no-default-features \
#     --git https://github.com/ms-jpq/sad --branch senpai
# RUN git clone --depth 1 https://github.com/ms-jpq/sad \
    # && cargo install --force --no-default-features --locked --all-features --path sad
# RUN cargo +nightly install --force --no-default-features \
    # sad

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

# FROM rust-base AS racer
# RUN cargo +nightly install --force  \
#     racer

FROM rust-base AS cargo-watch
RUN cargo install cargo-watch

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

# COPY --from=nix-lsp /root/.cargo/bin/nix-lsp /root/.cargo/bin/nix-lsp
# COPY --from=sad /root/.cargo/bin/sad /root/.cargo/bin/sad
# COPY --from=starship /root/.cargo/bin/starship /root/.cargo/bin/starship
COPY --from=bat /root/.cargo/bin/bat /root/.cargo/bin/bat
COPY --from=bottom /root/.cargo/bin/btm /root/.cargo/bin/btm
COPY --from=cargo-asm /root/.cargo/bin/cargo-asm /root/.cargo/bin/cargo-asm
COPY --from=cargo-binutils /root/.cargo/bin/cargo-* /root/.cargo/bin/
COPY --from=cargo-binutils /root/.cargo/bin/rust-* /root/.cargo/bin/
COPY --from=cargo-check /root/.cargo/bin/cargo-check /root/.cargo/bin/cargo-check
COPY --from=cargo-expand /root/.cargo/bin/cargo-expand /root/.cargo/bin/cargo-expand
# COPY --from=cargo-src /root/.cargo/bin/cargo-src /root/.cargo/bin/cargo-src
COPY --from=cargo-tree /root/.cargo/bin/cargo-tree /root/.cargo/bin/cargo-tree
COPY --from=cargo-watch /root/.cargo/bin/cargo-watch /root/.cargo/bin/cargo-watch
COPY --from=delta /root/.cargo/bin/delta /root/.cargo/bin/delta
COPY --from=dutree /root/.cargo/bin/dutree /root/.cargo/bin/dutree
COPY --from=exa /root/.cargo/bin/exa /root/.cargo/bin/exa
COPY --from=fd /root/.cargo/bin/fd /root/.cargo/bin/fd
COPY --from=gping /root/.cargo/bin/gping /root/.cargo/bin/gping
COPY --from=hyperfine /root/.cargo/bin/hyperfine /root/.cargo/bin/hyperfine
COPY --from=procs /root/.cargo/bin/procs /root/.cargo/bin/procs
# COPY --from=racer /root/.cargo/bin/racer /root/.cargo/bin/racer
COPY --from=rg /root/.cargo/bin/rg /root/.cargo/bin/rg
COPY --from=rust-base /root/.cargo /root/.cargo
COPY --from=sd /root/.cargo/bin/sd /root/.cargo/bin/sd
COPY --from=tokei /root/.cargo/bin/tokei /root/.cargo/bin/tokei
COPY --from=rust-base /root/.cargo/bin/rustc /root/.cargo/bin/rustc
COPY --from=rust-base /root/.cargo/bin/rustup /root/.cargo/bin/rustup
COPY --from=rust-base /root/.rustup/settings.toml /root/.rustup/settings.toml
COPY --from=rust-base /root/.rustup/toolchains /root/.rustup/toolchains
