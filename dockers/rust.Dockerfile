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

FROM kpango/rust:latest AS old

FROM rust-base AS bandwhich
RUN cargo +nightly install --force --no-default-features \
    bandwhich

FROM rust-base AS bat
RUN rustup update stable \
    && rustup default stable \
    && cargo install --force --locked \
    bat

FROM rust-base AS bottom
RUN rustup update stable \
    && rustup default stable \
    && cargo install --force --no-default-features \
    --git https://github.com/ClementTsang/bottom

FROM rust-base AS broot
RUN cargo +nightly install --force --no-default-features \
    broot

FROM rust-base AS cargo-asm
RUN cargo install cargo-asm

FROM rust-base AS cargo-binutils
RUN cargo install --git https://github.com/japaric/cargo-binutils

FROM rust-base AS cargo-bloat
RUN cargo install --force --no-default-features \
    --git https://github.com/RazrFalcon/cargo-bloat

FROM rust-base AS cargo-check
RUN cargo install cargo-check

FROM rust-base AS cargo-edit
RUN cargo install cargo-edit

FROM rust-base AS cargo-expand
RUN cargo install cargo-expand

FROM rust-base AS cargo-fix
RUN cargo +nightly install --force --no-default-features \
    cargo-fix

FROM rust-base AS cargo-tree
RUN cargo install cargo-tree

FROM rust-base AS cargo-watch
RUN cargo install cargo-watch

FROM rust-base AS delta
RUN cargo +nightly install --force --no-default-features \
    git-delta

# FROM rust-base AS deno
# RUN RUST_BACKTRACE=full cargo install --force --locked --all-features \
#     deno

FROM rust-base AS dog
RUN cargo install --force --no-default-features \
    --git https://github.com/ogham/dog dog

FROM rust-base AS dutree
RUN cargo +nightly install --force --no-default-features \
    dutree

FROM rust-base AS erdtree
RUN cargo +nightly install --force --no-default-features \
    erdtree

FROM rust-base AS exa
RUN cargo +nightly install --force --no-default-features \
    exa

FROM rust-base AS fd
RUN cargo install --force --no-default-features \
    --git https://github.com/sharkdp/fd

# FROM rust-base AS frawk
# RUN apt update -y \
#     && apt upgrade -y \
#     && wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - \
#     && apt install -y --no-install-recommends --fix-missing \
#     libllvm16 \
#     llvm-16 \
#     llvm-16-dev
# RUN cargo +nightly install --locked --force \
#     --features use_jemalloc,allow_avx2,unstable \
#     --git https://github.com/ezrosent/frawk frawk

FROM rust-base AS gping
RUN rustup update stable \
    && rustup default stable \
    && cargo install --force --no-default-features \
    gping

FROM rust-base AS hyperfine
RUN cargo +nightly install --force --no-default-features \
    hyperfine

FROM rust-base AS lsd
RUN cargo install --force --no-default-features \
    --git https://github.com/Peltoche/lsd --branch master

# FROM rust-base AS nushell
# RUN cargo install --force --features=extra \
#     --git https://github.com/nushell/nushell nu

FROM rust-base AS procs
RUN cargo install --force --no-default-features \
    --git https://github.com/dalance/procs

FROM rust-base AS rg
# RUN rustup update stable \
    # && rustup default stable \
    # && RUSTFLAGS="-C target-cpu=native" \
RUN RUSTFLAGS="-C target-cpu=native" \
    RUSTC_BOOTSTRAP=1 \
    cargo +nightly install --force --features 'pcre2 simd-accel' \
    ripgrep

FROM rg AS rga
RUN cargo install --locked --force --no-default-features \
    ripgrep_all

FROM rust-base AS rnix-lsp
RUN cargo install --force --no-default-features \
    --git https://github.com/nix-community/rnix-lsp

FROM rust-base AS sad
RUN git clone --depth 1 https://github.com/ms-jpq/sad \
    && cd sad \
    && cargo install --force --locked --all-features --path .

FROM rust-base AS sd
RUN cargo +nightly install --force --no-default-features \
    sd

FROM rust-base AS shellharden
RUN cargo +nightly install --force --no-default-features \
    shellharden

# FROM old AS starship
FROM rust-base AS starship
RUN cargo +nightly install --force --no-default-features starship
# RUN rustup update stable \
    # && rustup default stable \
    # && cargo install --force --no-default-features
# RUN cargo install --locked starship

FROM rust-base AS t-rec
RUN cargo +nightly install --force --no-default-features \
    t-rec

FROM rust-base AS tokei
RUN cargo +nightly install --force --no-default-features \
    tokei

FROM rust-base AS tree-sitter
RUN cargo +nightly install --force --no-default-features \
    tree-sitter-cli

# FROM rust-base AS watchexec
# # RUN cargo +nightly install --force --no-default-features \
# RUN rustup update stable \
#     && rustup default stable \
#     && cargo install watchexec-cli

FROM rust-base AS xh
RUN cargo +nightly install --force --locked --all-features \
    xh

FROM scratch AS rust
ENV HOME /root
ENV RUSTUP ${HOME}/.rustup
ENV CARGO ${HOME}/.cargo
ENV BIN_PATH ${CARGO}/bin

# COPY --from=frawk ${BIN_PATH}/frawk ${BIN_PATH}/frawk
# COPY --from=nushell ${BIN_PATH}/nu ${BIN_PATH}/nu
COPY --from=bandwhich ${BIN_PATH}/bandwhich ${BIN_PATH}/bandwhich
COPY --from=bat ${BIN_PATH}/bat ${BIN_PATH}/bat
COPY --from=bottom ${BIN_PATH}/btm ${BIN_PATH}/btm
COPY --from=broot ${BIN_PATH}/broot ${BIN_PATH}/broot
COPY --from=cargo-asm ${BIN_PATH}/cargo-asm ${BIN_PATH}/cargo-asm
COPY --from=cargo-binutils ${BIN_PATH}/cargo-* ${BIN_PATH}/
COPY --from=cargo-binutils ${BIN_PATH}/rust-* ${BIN_PATH}/
COPY --from=cargo-bloat ${BIN_PATH}/cargo-bloat ${BIN_PATH}/cargo-bloat
COPY --from=cargo-check ${BIN_PATH}/cargo-check ${BIN_PATH}/cargo-check
COPY --from=cargo-edit ${BIN_PATH}/cargo-add ${BIN_PATH}/cargo-add
COPY --from=cargo-edit ${BIN_PATH}/cargo-rm ${BIN_PATH}/cargo-rm
COPY --from=cargo-edit ${BIN_PATH}/cargo-set-version ${BIN_PATH}/cargo-set-version
COPY --from=cargo-edit ${BIN_PATH}/cargo-upgrade ${BIN_PATH}/cargo-upgrade
COPY --from=cargo-expand ${BIN_PATH}/cargo-expand ${BIN_PATH}/cargo-expand
COPY --from=cargo-fix ${BIN_PATH}/cargo-fix ${BIN_PATH}/cargo-fix
COPY --from=cargo-tree ${BIN_PATH}/cargo-tree ${BIN_PATH}/cargo-tree
COPY --from=cargo-watch ${BIN_PATH}/cargo-watch ${BIN_PATH}/cargo-watch
COPY --from=delta ${BIN_PATH}/delta ${BIN_PATH}/delta
# COPY --from=deno ${BIN_PATH}/deno ${BIN_PATH}/deno
COPY --from=dog ${BIN_PATH}/dog ${BIN_PATH}/dog
COPY --from=dutree ${BIN_PATH}/dutree ${BIN_PATH}/dutree
COPY --from=erdtree ${BIN_PATH}/erd ${BIN_PATH}/erd
COPY --from=exa ${BIN_PATH}/exa ${BIN_PATH}/exa
COPY --from=fd ${BIN_PATH}/fd ${BIN_PATH}/fd
COPY --from=gping ${BIN_PATH}/gping ${BIN_PATH}/gping
COPY --from=hyperfine ${BIN_PATH}/hyperfine ${BIN_PATH}/hyperfine
COPY --from=lsd ${BIN_PATH}/lsd ${BIN_PATH}/lsd
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
COPY --from=shellharden ${BIN_PATH}/shellharden ${BIN_PATH}/shellharden
COPY --from=starship ${BIN_PATH}/starship ${BIN_PATH}/starship
COPY --from=t-rec ${BIN_PATH}/t-rec ${BIN_PATH}/t-rec
COPY --from=tokei ${BIN_PATH}/tokei ${BIN_PATH}/tokei
COPY --from=tree-sitter ${BIN_PATH}/tree-sitter ${BIN_PATH}/tree-sitter
# COPY --from=watchexec ${BIN_PATH}/watchexec ${BIN_PATH}/watchexec
COPY --from=xh ${BIN_PATH}/xh ${BIN_PATH}/xh
