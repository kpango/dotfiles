FROM kpango/rust-musl-builder:latest AS rust

# RUN cargo install --force --no-default-features --all-features --bins --git https://github.com/rust-lang/rust \
#     && cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
# RUN --mount=type=cache,target=/root/.cache/sccache \
#     && cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
RUN cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
    && cargo install --force --no-default-features --git https://github.com/mozilla/sccache \
    && RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://gitlab.com/jD91mZM2/nix-lsp \
    && RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/RazrFalcon/cargo-bloat \
    && RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features --git https://github.com/sharkdp/fd \
    && RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features ripgrep \
    && RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features exa \
    && RUSTC_WRAPPER=`which sccache` cargo install --force --no-default-features bat

