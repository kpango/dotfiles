FROM kpango/dev-base:latest AS rust-base

ARG TOOLCHAIN=nightly

ENV PATH /root/.cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN rustup install nightly \
    && rustup default nightly \
    && rustup update

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

FROM rust-base AS sad
RUN git clone https://github.com/ms-jpq/sad \
    && cargo +nightly install --locked --all-features --path sad
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
# RUN cargo +nightly install --force --no-default-features \
    # bottom

FROM rust-base AS tokei
RUN cargo +nightly install --force --no-default-features \
    tokei

FROM scratch AS rust

# COPY --from=nix-lsp /root/.cargo/bin/nix-lsp /root/.cargo/bin/nix-lsp
# COPY --from=starship /root/.cargo/bin/starship /root/.cargo/bin/starship
COPY --from=bat /root/.cargo/bin/bat /root/.cargo/bin/bat
COPY --from=bottom /root/.cargo/bin/btm /root/.cargo/bin/btm
COPY --from=delta /root/.cargo/bin/delta /root/.cargo/bin/delta
COPY --from=dutree /root/.cargo/bin/dutree /root/.cargo/bin/dutree
COPY --from=exa /root/.cargo/bin/exa /root/.cargo/bin/exa
COPY --from=fd /root/.cargo/bin/fd /root/.cargo/bin/fd
COPY --from=gping /root/.cargo/bin/gping /root/.cargo/bin/gping
COPY --from=hyperfine /root/.cargo/bin/hyperfine /root/.cargo/bin/hyperfine
COPY --from=procs /root/.cargo/bin/procs /root/.cargo/bin/procs
COPY --from=rg /root/.cargo/bin/rg /root/.cargo/bin/rg
COPY --from=rust-base /root/.cargo /root/.cargo
COPY --from=sad /root/.cargo/bin/sad /root/.cargo/bin/sad
COPY --from=sd /root/.cargo/bin/sd /root/.cargo/bin/sd
COPY --from=tokei /root/.cargo/bin/tokei /root/.cargo/bin/tokei
