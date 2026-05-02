{ config, pkgs, lib, ... }:

{
  # ────────────────────────────────────────────────
  # Shell: zsh (system-wide default)
  # ────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    # autosuggestions, syntax highlighting, completion are handled by
    # sheldon plugin manager at the user level; keep system config minimal.
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autosuggestions.enable = true;
    histSize = 1000000;
    # Global env vars expected by the dotfiles zshrc
    shellInit = ''
      export EDITOR=hx
      export VISUAL=hx
      export PAGER=less
      export LESS="-R"
    '';
  };
  users.defaultShell = pkgs.zsh;

  # ────────────────────────────────────────────────
  # tmux
  # ────────────────────────────────────────────────
  programs.tmux = {
    enable = true;
    clock24 = true;
    historyLimit = 1000000;
    mouse = true;
    terminal = "tmux-256color";
    keyMode = "vi";
    aggressiveResize = true;
    # Additional config sourced from dotfiles
    extraConfig = ''
      set -g base-index 1
      setw -g pane-base-index 1
      set -g automatic-rename on
      set -g automatic-rename-format '#{b:pane_current_path}'
      set-option -g set-titles on
      set -g focus-events on
      setw -g monitor-activity on
      setw -g visual-activity on
      setw -g alternate-screen on
      set -g status-keys vi

      bind c new-window -c '#{pane_current_path}'
      bind s split-window -v -c '#{pane_current_path}'
      bind v split-window -h -c '#{pane_current_path}'
      bind-key -r a setw synchronize-panes \; display "synchronize-panes #{?pane_synchronized,on,off}"
      bind-key -r C-j resize-pane -D 5
      bind-key -r C-k resize-pane -U 5
      bind-key -r C-h resize-pane -L 5
      bind-key -r C-l resize-pane -R 5

      set -g @plugin 'tmux-plugins/tpm'
      set -g @plugin 'tmux-plugins/tmux-cpu'
      set -g @cpu_interval 5
    '';
  };

  # ────────────────────────────────────────────────
  # Git (system-level)
  # ────────────────────────────────────────────────
  programs.git = {
    enable = true;
    config = {
      core = {
        autocrlf = false;
        editor = "hx";
        pager = "delta";
        fileMode = false;
        quotepath = false;
        precomposeunicode = true;
      };
      color.ui = "auto";
      push = {
        default = "tracking";
        autoSetupRemote = true;
      };
      pull = {
        rebase = true;
        ff = "only";
      };
      diff = {
        mnemonicprefix = true;
        patience = true;
        indentHeuristic = true;
        colorMoved = "default";
      };
      http.postBuffer = 524288000;
      help.autocorrect = 0;
      alias = {
        ad = "add";
        cam = "commit -a --amend";
        ci = "commit -a";
        cm = "commit";
        co = "checkout";
        ft = "fetch";
        rbm = "rebase main";
        sh = "show";
        so = "remote show origin";
        st = "status";
        stt = "status -uno -u";
        up = "pull --rebase";
        ba = "branch -a";
        bm = "branch --merged";
        bn = "branch --no-merged";
        br = "branch";
        la = "log --pretty=format:'%ad %h (%an): %s' --date=short";
        lp = "log -p";
      };
    };
  };

  # ────────────────────────────────────────────────
  # Development tools & language toolchains
  # Derived from pacman -Qe output
  # ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # ── Core CLI tools ──
    axel
    bat
    bottom
    btop
    ccache
    clang
    cmake
    curl
    delta # git-delta
    dmidecode
    duf
    ethtool
    fd
    file
    fzf
    ghostty # terminal (if available in nixpkgs, else skip)
    git
    git-delta
    graphviz
    grep
    gzip
    helix
    htop
    imagemagick
    inetutils
    iproute2
    iptables
    irqbalance
    jq
    less
    lsd
    lshw
    make
    mdadm
    mtr
    nmap
    nvme-cli
    parted
    patch
    pciutils
    procs
    python3
    ranger
    rclone
    ripgrep
    sed
    smartmontools
    starship
    tar
    tig
    tmux
    unrar
    unzip
    usbutils
    wget
    which
    whois
    xfsprogs
    yt-dlp
    zoxide
    zsh

    # ── Go toolchain ──
    go
    gotools
    gopls
    delve

    # ── Rust toolchain ──
    rustup

    # ── Node / Bun ──
    nodejs
    nodePackages.typescript-language-server

    # ── Container / Kubernetes ──
    docker-compose
    docker-buildx
    kubectl
    kubectx
    k3d

    # ── Cloud / Infra ──
    google-cloud-sdk
    rclone
    tailscale

    # ── System / hardware ──
    acpi
    amdgpu-fan
    dosfstools
    efibootmgr
    fakeroot
    fwupd
    lm_sensors
    patchelf
    powertop
    psensor
    sysfsutils
    usbutils
    wakeonlan

    # ── Editors / LSP ──
    nil # Nix LSP
    nixpkgs-fmt
    bash-language-server
    marksman
    taplo

    # ── Fonts ──
    nerd-fonts.hack

    # ── Misc ──
    atuin
    sheldon
    ghq
    pass
    gnupg
    openssl
  ];

  # ────────────────────────────────────────────────
  # Tailscale VPN
  # ────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ────────────────────────────────────────────────
  # SSH daemon
  # ────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    extraConfig = "StreamLocalBindUnlink yes";
  };

  # ────────────────────────────────────────────────
  # NTP — chrony with Japanese pool servers
  # ────────────────────────────────────────────────
  services.chrony = {
    enable = true;
    servers = [
      "0.jp.pool.ntp.org"
      "1.jp.pool.ntp.org"
      "2.jp.pool.ntp.org"
      "3.jp.pool.ntp.org"
      "ntp.nict.jp"
      "time.google.com"
    ];
    extraConfig = ''
      minsources 2
      makestep 1.0 3
      leapsecmode slew
      rtcsync
    '';
  };

  # ────────────────────────────────────────────────
  # Starship prompt (system-wide init)
  # ────────────────────────────────────────────────
  programs.starship = {
    enable = true;
  };

  # ────────────────────────────────────────────────
  # Atuin — shell history sync
  # ────────────────────────────────────────────────
  programs.atuin.enable = true;

  # ────────────────────────────────────────────────
  # Wayland / Sway compositor
  # ────────────────────────────────────────────────
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaybg
      swayidle
      swaylock
      waybar
      wofi
      mako
      grim
      slurp
      wl-clipboard
      kanshi
      wdisplays
    ];
  };

  # ────────────────────────────────────────────────
  # Fcitx5 Japanese input
  # ────────────────────────────────────────────────
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
  };

  # ────────────────────────────────────────────────
  # Audio: PipeWire
  # ────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };
  hardware.pulseaudio.enable = false; # replaced by pipewire-pulse

  # ────────────────────────────────────────────────
  # sudo: passwordless for wheel group
  # ────────────────────────────────────────────────
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
    extraConfig = ''
      Defaults !always_set_home
      Defaults env_keep+="HOME"
    '';
  };
}
