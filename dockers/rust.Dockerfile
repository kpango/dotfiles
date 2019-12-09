FROM kpango/rust-musl-builder:latest AS rust-base

# RUN cargo install --force --no-default-features --all-features --bins --git https://github.com/rust-lang/rust \
#     && cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
# RUN --mount=type=cache,target=/root/.cache/sccache \
#     && cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
# RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache
RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache


FROM rust-base AS nix-lsp
RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://gitlab.com/jD91mZM2/nix-lsp

# FROM rust-base AS cargo-bloat
# RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/RazrFalcon/cargo-bloat

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
# RUN RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/BurntSushi/ripgrep
# RUN set -x \
#     && curl -o ripgrep.tar.gz \
#     https://github.com/BurntSushi/ripgrep/releases/download/11.0.2/ripgrep-11.0.2-x86_64-unknown-linux-musl.tar.gz \
#     && tar xzvf ripgrep.tar.gz \
#     && ./rg --version \
#     && mv ./rg /home/rust/.cargo/rg

FROM kpango/rust-musl-builder:latest AS rust

COPY --from=nix-lsp /home/rust/.cargo/bin/nix-lsp /root/.cargo/bin/nix-lsp
COPY --from=fd /home/rust/.cargo/bin/fd /root/.cargo/bin/fd
COPY --from=exa /home/rust/.cargo/bin/exa /root/.cargo/bin/exa
COPY --from=starship /home/rust/.cargo/bin/starship /root/.cargo/bin/starship
COPY --from=bat /home/rust/.cargo/bin/bat /root/.cargo/bin/bat
COPY --from=rg /home/rust/.cargo/bin/rg /root/.cargo/bin/rg
