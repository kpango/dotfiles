FROM kpango/dev-base:latest AS rust-base

ARG TOOLCHAIN=nightly

ENV PATH /root/.cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain $TOOLCHAIN

RUN rustup install nightly \
    && rustup default nightly \
    && rustup update

RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache

FROM rust-base AS procs
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/dalance/procs

FROM rust-base AS nix-lsp
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://gitlab.com/jD91mZM2/nix-lsp

FROM rust-base AS cargo-bloat
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/RazrFalcon/cargo-bloat

FROM rust-base AS fd
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/sharkdp/fd

FROM rust-base AS starship
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/starship/starship

FROM rust-base AS exa
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features exa

FROM rust-base AS bat
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features bat

FROM rust-base AS rg
RUN RUST_BACKTRACE=1 RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features ripgrep

# RUN cargo install --force --no-default-features --all-features --bins --git https://github.com/rust-lang/rust \
#     && cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
# RUN --mount=type=cache,target=/root/.cache/sccache \
#     && cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
# RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache

FROM scratch AS rust

COPY --from=nix-lsp /home/rust/.cargo/bin/nix-lsp /root/.cargo/bin/nix-lsp
COPY --from=fd /home/rust/.cargo/bin/fd /root/.cargo/bin/fd
COPY --from=exa /home/rust/.cargo/bin/exa /root/.cargo/bin/exa
COPY --from=starship /home/rust/.cargo/bin/starship /root/.cargo/bin/starship
COPY --from=bat /home/rust/.cargo/bin/bat /root/.cargo/bin/bat
COPY --from=rg /home/rust/.cargo/bin/rg /root/.cargo/bin/rg
