{ config, pkgs, lib, username, ... }:

{
  # User level tools and configuration
  home.username = "${username}";
  home.homeDirectory = "/Users/${username}";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the manual before changing.

  # All required CLI & GUI packages to install via Nixpkgs
  home.packages = with pkgs; [
    # CLI Tools
    ghostty
    zsh
    helix
    tmux
    git
    go
    rustup
    ghq
    tig
    fd
    axel
    cmake
    jq
    k3d
    k9s
    kubectl
    lua
    gnumake
    pass
    procs
    ugrep
    wakeonlan
    wget

    # GUI Tools
    zed-editor

    # Container Runtimes
    colima
    docker
  ];

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # The required Colima alias for extreme speed on Apple Silicon
    shellAliases = {
      colima-fast = "colima start --cpu 6 --memory 12 --disk 100 --arch aarch64 --vm-type vz --vz-rosetta";
    };
  };

  # Helix setup (can be expanded later)
  programs.helix = {
    enable = true;
    settings = {
      theme = "default";
    };
  };

  # Tmux setup
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
  };

  # Git setup
  programs.git = {
    enable = true;
    userName = "${username}";
    userEmail = "${username}@local.dev";
    # You might want to update userName and userEmail later
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
