FROM kpango/dev-base:latest AS rust-base

ARG TOOLCHAIN=nightly

ENV PATH /root/.cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN rustup install nightly \
    && rustup default nightly \
    && rustup update

RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache

FROM rust-base AS nix-lsp
RUN cargo install --force --no-default-features \
    --git https://gitlab.com/jD91mZM2/nix-lsp

FROM rust-base AS cargo-bloat
RUN cargo install --force --no-default-features \
    --git https://github.com/RazrFalcon/cargo-bloat

FROM rust-base AS fd
RUN cargo install --force --no-default-features \
    --git https://github.com/sharkdp/fd

FROM rust-base AS starship
RUN cargo install --force --no-default-features \
    --git https://github.com/starship/starship

FROM rust-base AS exa
RUN cargo +nightly install --verbose --force \
    exa

FROM rust-base AS rg
RUN cargo +nightly install --verbose --force --no-default-features \
    ripgrep

FROM rust-base AS procs
RUN cargo install --force --no-default-features \
    --git https://github.com/dalance/procs

FROM rust-base AS bat
RUN cargo +nightly install --verbose --force --locked  --no-default-features \
    --git https://github.com/sharkdp/bat

FROM scratch AS rust

COPY --from=rust-base /root/.cargo /root/.cargo
# COPY --from=nix-lsp /root/.cargo/bin/nix-lsp /root/.cargo/bin/nix-lsp
COPY --from=fd /root/.cargo/bin/fd /root/.cargo/bin/fd
COPY --from=exa /root/.cargo/bin/exa /root/.cargo/bin/exa
COPY --from=starship /root/.cargo/bin/starship /root/.cargo/bin/starship
COPY --from=bat /root/.cargo/bin/bat /root/.cargo/bin/bat
COPY --from=rg /root/.cargo/bin/rg /root/.cargo/bin/rg
