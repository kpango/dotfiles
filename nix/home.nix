{ config, pkgs, lib, username, hostname, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # Define shared packages
  sharedPackages = with pkgs; [
    axel
    bun
    ccache
    cmake
    fd
    fastfetch
    fwupd
    gettext
    ghq
    ghostty
    git
    gnumake
    go
    graphviz
    helix
    jq
    k3d
    k9s
    kubectl
    lsd
    lshw
    lua
    make
    mdadm
    mtr
    nmap
    pass
    procs
    ripgrep
    rustup
    sed
    sheldon
    starship
    tar
    tig
    tmux
    ugrep
    unzip
    wakeonlan
    wget
    zsh
    # Extra Arch Linux dependencies explicitly requested
    alsa-utils
    btop
  ];

  # Define Darwin-specific packages
  darwinPackages = with pkgs; [
    colima
    docker
    zed-editor
  ];

  # Define Linux-specific packages
  linuxPackages = with pkgs; [
    grim
    kanshi
    light
    mako
    noto-fonts-emoji
    pavucontrol
    slurp
    sway
    swaybg
    swayidle
    waybar
    wl-clipboard
    wofi
    xfce.thunar
  ];

in
{
  # User level tools and configuration
  home = {
    username = "${username}";
    homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
    stateVersion = "23.11";
    # Shared packages across all platforms
    packages = sharedPackages
      ++ lib.optionals isDarwin darwinPackages
      ++ lib.optionals isLinux linuxPackages;
  };

  # Symlink dotfiles from the repository root natively using Home Manager
  home.file = {
    # Ghostty Config
    ".config/ghostty/config".source = ../ghostty.conf;

    # Sheldon Config
    ".config/sheldon/plugins.toml".source = ../sheldon.toml;

    # Starship Config
    ".config/starship.toml".source = ../starship.toml;

    # SSH Config
    ".ssh/config".source = ../sshconfig;

    # Aliases
    ".aliases".source = ../alias;

    # Tmux specific configs
    ".tmux-kube".source = ../tmux-kube;
    ".tmux.new-session".source = ../tmux.new-session;

    # Helix Configs
    ".config/helix/config.toml".source = ../helix/config.toml;
    ".config/helix/languages.toml".source = ../helix/languages.toml;
    ".config/helix/themes".source = ../helix/themes;
  } // lib.optionalAttrs isLinux {
    # Mako Config
    ".config/mako/config".source = ../arch/mako.conf;

    # Kanshi Config
    ".config/kanshi/config".source = ../arch/kanshi.conf;

    # Workstyle Config
    ".config/workstyle/config.toml".source = ../arch/workstyle.toml;

    # Waybar Config
    ".config/waybar/config".source = ../arch/waybar.json;
    ".config/waybar/style.css".source = ../arch/waybar.css;

    # Sway Config
    ".config/sway/config".source = ../arch/sway.conf;

    # Wofi Config
    ".config/wofi/config".source = ../arch/wofi/wofi.conf;
    ".config/wofi/style.css".source = ../arch/wofi/style.css;

    # Ranger Config
    ".config/ranger".source = ../arch/ranger;
  };

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Source the root dotfiles natively inside Zsh's init sequence
    initExtra = ''
      # Source aliases
      source ~/.aliases

      # Init Sheldon
      eval "$(sheldon source)"

      # Init Starship
      eval "$(starship init zsh)"

      # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
      source ${../zshrc}
    '';

    shellAliases = lib.optionalAttrs isDarwin {
      colima-fast = "colima start --cpu 6 --memory 12 --disk 100 --arch aarch64 --vm-type vz --vz-rosetta";
    };
  };

  # Helix setup (handled natively by symlinks above, but enable it in Nix)
  programs.helix.enable = true;

  # Tmux setup
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    # Embed existing tmux.conf directly into the Home Manager config
    extraConfig = builtins.readFile ../tmux.conf;
  };

  # Git setup
  programs.git = {
    enable = true;
    userName = "${username}";
    userEmail = "${username}@local.dev";

    # Incorporate the root .gitignore and .gitconfig contents
    # Since existing `.gitconfig` has a lot of custom logic, we can inject it via extraConfig.
    extraConfig = {
      core = {
        excludesfile = "${../gitignore}";
      };
    };

    # Append the raw gitconfig if necessary, or let Home Manager handle it.
    # To avoid clashes with native Home Manager git blocks, we use an include path:
    includes = [
      {
        path = "${../gitconfig}";
      }
    ];
  };



  # Linux dependencies are managed via packages,
  # and all configurations are managed natively by symlinking
  # the single-source-of-truth files from the `arch/` directory.
  # We do not use Home Manager's native modules for sway, waybar, or wofi
  # to prevent duplicate file definition errors.

  programs.home-manager.enable = true;
}
