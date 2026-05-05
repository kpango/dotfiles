{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # C / C++
    ccache
    clang-tools
    cmake
    gcc
    gnumake
    llvm

    # Go
    buf
    delve
    go
    go-task
    gofumpt
    golangci-lint
    golangci-lint-langserver
    gopls
    gosec
    tinygo

    # Rust
    rustup

    # Python
    python3
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

    # Other Languages
    dart
    lua
    nim
    zig
    zls

    # K8s / Cloud
    google-cloud-sdk
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
    kubectx
    kubernetes-helm
    kustomize
    linkerd
    skaffold
    stern
    talosctl
    trivy

    # CLI / Utilities
    actionlint
    air
    axel
    bat
    bottom
    btop
    coreutils
    curl
    direnv
    delta
    dnsmasq
    duf
    dutree
    eza
    fastfetch
    fd
    findutils
    fzf
    gawk
    gettext
    ghq
    git
    git-crypt
    gnupg
    graphviz
    gzip
    hugo
    hyperfine
    imagemagick
    inetutils
    jq
    less
    lsd
    lsof
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
    gnused
    sheldon
    shellcheck
    shfmt
    starship
    stylua
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
    zsh
  ];
}
