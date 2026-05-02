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
    gotools
    tinygo

    # Rust
    rust-analyzer
    rustup

    # Python
    python3
    pyright
    ruff
    ruff-lsp

    # Node / JS / Web
    bun
    deno
    nodejs
    nodePackages.bash-language-server
    nodePackages.dockerfile-language-server-nodejs
    nodePackages.prettier
    nodePackages.typescript
    nodePackages.typescript-language-server
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
    octant
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
    ghostty
    git
    gnupg
    graphviz
    gzip
    helix
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
    sed
    sheldon
    shfmt
    starship
    stylua
    taplo
    tar
    thefuck
    tig
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
