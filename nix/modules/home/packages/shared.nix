{
  pkgs,
  lib,
  ...
}:

# `prmt` in the list below now resolves to nixpkgs' package rather than a local
# copy. The local pkgs/prmt.nix pinned v0.5.0 and built from source, which meant
# fetchCargoVendor had to reach crates.io at build time — that fails outright
# behind a TLS-intercepting proxy, because the build sandbox uses nixpkgs'
# `cacert` bundle and cannot see a corporate root CA. Upstream ships v0.7.0
# prebuilt in the binary cache, so no crates.io access is needed at all.
{
  home.packages = with pkgs; [
    # C / C++
    ccache
    # dockers/base.Dockerfile apt-installs the plain `clang` compiler alongside
    # clang-tools/llvm; the bare compiler binary was missing here.
    clang
    clang-tools
    cmake
    # Both clang and gcc provide generic bin/{cc,c++,cpp} symlinks, which
    # collide when home-manager merges home.packages into one profile via
    # pkgs.buildEnv ("two given paths contain a conflicting subpath").
    # lib.lowPrio alone doesn't help here: cc-wrapper packages already carry
    # meta.priority = 10 by default (verified via `nix eval
    # ...home.packages --apply '...meta.priority...'`: clang-wrapper's own
    # priority is already 10), and lowPrio also sets exactly 10 — an equal
    # priority is still a tie, which buildEnv still treats as a hard conflict.
    # setPrio 20 gives gcc a strictly higher (i.e. lower-precedence) number so
    # buildEnv resolves in clang's favor (matching macOS's native Xcode/clang
    # toolchain) while gcc/g++ stay fully available under their own specific
    # names.
    (lib.setPrio 20 gcc)
    gnumake
    lld
    llvm
    # dockers/base.Dockerfile apt-installs pkg-config, and dockers/{base,arch
    # pkg.list} both need it for build dependency resolution. gfortran is
    # deliberately NOT added here: it's a cc-wrapper derivative that ships the
    # exact same bin/{cc,gcc,c++,cpp,g++} symlink set as gcc/clang (verified
    # via a scratch-store buildEnv comparison), so it would collide with the
    # existing clang/gcc priority dance above rather than add anything new.
    pkg-config
    universal-ctags

    # Go
    buf
    delve
    errcheck
    go
    go-task
    go-tools # staticcheck
    gofumpt
    golangci-lint
    golangci-lint-langserver
    gopls
    gosec
    gotestfmt
    grpcurl
    protoc-gen-go
    tinygo

    # Rust
    # rustup manages the toolchain itself; everything below is a prebuilt
    # nixpkgs binary (matches dockers/rust.Dockerfile's `cargo binstall` list),
    # not something that needs building via the rustup-managed cargo.
    rustup
    ast-grep
    bandwhich
    broot
    cargo-binutils
    cargo-bloat
    cargo-edit
    cargo-expand
    cargo-machete
    cargo-show-asm
    cargo-watch
    erdtree
    frawk
    gping
    hx-lsp
    lsp-ai
    nushell
    prek
    ripgrep-all
    sad
    sd
    shellharden
    tokei
    t-rec
    tree-sitter
    typos
    typos-lsp
    watchexec
    xh
    zoxide

    # Python
    python3
    # dockers/base.Dockerfile apt-installs python3-pip alongside python3; pip
    # is a separate nixpkgs derivation, not bundled with the interpreter.
    python3Packages.pip
    pyright
    ruff

    # Node / JS / Web
    bun
    deno
    nodejs
    bash-language-server
    dockerfile-language-server
    prettier
    typescript
    typescript-language-server
    vscode-langservers-extracted
    yaml-language-server

    # AI CLI assistants (dockers/tools.Dockerfile installs these via
    # `bun install -g`; nixpkgs ships prebuilt equivalents). @byterover/cipher
    # and @google/jules have no nixpkgs equivalent (nixpkgs' own `cipher` is
    # an unrelated elementary-OS text encoder, not byterover/cipher) — left
    # as npm-global installs.
    claude-code
    # nixpkgs attr for npm's @colbymchenry/codegraph (same upstream project,
    # same homepage/description) — used as an MCP server, see CLAUDE.md.
    codegraph
    codex
    copilot-language-server
    # nixpkgs attr providing the `agy` binary — Google's Antigravity CLI
    # (successor to Gemini CLI); see ~/.agy/ config deployed via DOTFILES_MAP.
    antigravity-cli
    github-copilot-cli
    # nixpkgs attr for npm's `opencode-ai` — homepage matches
    # github.com/anomalyco/opencode, same project under a different name.
    opencode
    qwen-code

    # Other Languages
    dart
    # `lua` (PUC-Rio) removed — both it and luajit ship a `bin/lua`, and
    # pkgs.buildEnv hard-errors on the colliding path ("two given paths
    # contain a conflicting subpath"). luajit's `bin/lua` covers the CLI use
    # case; luarocks doesn't require the plain interpreter to be present.
    luajit
    luarocks
    nim
    zig
    zls

    # K8s / Cloud
    conftest
    google-cloud-sdk
    helm-docs
    helmfile
    istioctl
    k3d
    k9s
    kind
    krew
    kube-linter
    kubeconform
    kubebuilder
    kubecolor
    kubectl
    kubectl-gadget
    kubectl-tree
    kubectx
    kubefwd
    kubernetes-helm
    kustomize
    linkerd
    pulumi
    skaffold
    stern
    talosctl
    trivy
    # telepresence claims aarch64-darwin in meta.platforms but actually pulls
    # in conntrack-tools (Linux-only, hard dependency) at this pinned nixpkgs
    # revision — `nix build` fails outright ("Refusing to evaluate package
    # 'conntrack-tools' ... not available on aarch64-darwin"), a nixpkgs
    # packaging gap between declared and actual platform support. Left out
    # rather than worked around; revisit if a later nixpkgs revision fixes it.

    # Nix devtools (dockers/nix.Dockerfile's nix-devtools stage installs these
    # via `nix profile install`; mirrored here so the same tooling is
    # available outside the Docker image too). nixfmt-rfc-style itself is
    # intentionally NOT added here — Makefile.d/nix.mk's nix/fmt targets call
    # it via `nix run`, not a persistent home.packages install.
    deadnix
    nil
    nix-output-monitor
    nix-tree
    statix

    # CLI / Utilities
    actionlint
    air
    axel
    bat
    beautysh
    bottom
    btop
    coreutils
    curl
    direnv
    gitui
    dive
    dnsmasq
    docker-buildx
    docker-compose
    docker-credential-helpers
    dockfmt
    duf
    dutree
    eza
    fastfetch
    fd
    findutils
    # macOS has no flock(1) at all (util-linux is Linux-only); nixpkgs' own
    # `flock` package is an explicit cross-platform reimplementation. Several
    # swarm-* hook/skill scripts (e.g. harness-record.sh) assume it exists.
    flock
    flamegraph
    fzf
    gawk
    gettext
    gh
    ghq
    git
    git-crypt
    gnupg
    # dockers/tools.Dockerfile pip-installs a package named `graphifyy`, which
    # is not itself in nixpkgs, but it ships the same `graphify` binary that
    # zsh/05-functions.zsh's graphify() wrapper calls, and nixpkgs' own
    # `graphify` package provides that binary directly.
    graphify
    graphviz
    gzip
    hadolint
    # dockers/rust.Dockerfile fetches this from GitHub releases via download.mk's
    # generic install-tool (not cargo/apt); nixpkgs ships a prebuilt equivalent.
    herdr
    hugo
    hyperfine
    imagemagick
    inetutils
    jq
    less
    lsd
    lsof
    markdownlint-cli
    mbake
    mtr
    neovim
    ngrok
    nkf
    nmap
    pass
    patch
    procs
    protobuf
    ranger
    rclone
    ripgrep
    rtk
    gnused
    sheldon
    shellcheck
    shfmt
    prmt
    # Re-added 2026-08-06: was removed entirely (here and from
    # nixos/core/programs.nix) because jnsahaj/lumen didn't exist yet at the
    # flake's then-pinned nixpkgs revision — see nix/overlays/default.nix for
    # the full account. flake.lock now pins a revision (2026-08-05) where
    # `pkgs.lumen` resolves; verified with `nix eval --impure` directly
    # against the flake's own `inputs.nixpkgs`, not the always-current flake
    # registry (the registry gave a false positive the first time around).
    lumen
    stylua
    # Was isLinux-gated in packages/linux.nix alongside ALSA/PipeWire-specific
    # tools it has nothing to do with — sysbench is a generic CPU/memory/IO
    # benchmark with no Linux-only dependency, and nixpkgs builds it for
    # aarch64-darwin.
    sysbench
    taplo
    gnutar
    pay-respects
    tig
    tldr
    tmux
    tmux-xpanes
    translate-shell
    ugrep
    unrar
    unzip
    upx
    vegeta
    wakeonlan
    wget
    which
    whois
    wpscan
    yq-go
    yt-dlp
    zip
    zsh
    # dockers/rust.Dockerfile cargo-binstalls this; arch/aur_desk.list has
    # the matching AUR package (zsh-patina-bin) for the desk host.
    zsh-patina
  ];
}
