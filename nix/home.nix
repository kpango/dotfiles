{ config, pkgs, lib, username, hostname, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  # User level tools and configuration
  home.username = "${username}";
  home.homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
  home.stateVersion = "23.11";

  # Shared packages across all platforms
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

    # Extra Arch Linux dependencies explicitly requested
    alsa-utils
    ccache
    fastfetch
    fwupd
    gettext
    graphviz
    btop
    lsd
    lshw
    make
    mdadm
    mtr
    nmap
    ripgrep
    sed
    starship
    tar
    unzip
    bun
  ] ++ lib.optionals isDarwin [
    # macOS Specific
    zed-editor
    colima
    docker
  ] ++ lib.optionals isLinux [
    # Linux Specific Wayland & Tools from Arch configuration
    sway
    swaybg
    swayidle
    waybar
    wl-clipboard
    wofi
    mako
    kanshi
    grim
    slurp
    light
    pavucontrol
    xfce.thunar

    # Fonts specifically handled by user package
    noto-fonts-emoji
  ];

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      # The required Colima alias for extreme speed on Apple Silicon (only active on Darwin)
      colima-fast = if isDarwin then "colima start --cpu 6 --memory 12 --disk 100 --arch aarch64 --vm-type vz --vz-rosetta" else "";
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
  };

  # Linux Sway Configuration (mapped from arch/sway.conf)
  wayland.windowManager.sway = lib.mkIf isLinux {
    enable = true;
    config = {
      modifier = "Mod4";
      terminal = "ghostty -e zsh -c 'tmux -S /tmp/tmux.sock -q has-session && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n$USER -s$USER@$(hostname)'";
      menu = "wofi --show drun -i";
      bars = [{ command = "waybar"; }];
      fonts = {
        names = [ "HackGen35ConsoleNF" ];
        style = "Regular";
        size = 16.0;
      };
      output = {
        "*" = {
          bg = "~/.wallpapers/default.png fill";
          scale = "1.00";
        };
      };
      keybindings = lib.mkOptionDefault {
        "Mod4+Return" = "exec ghostty";
        "XF86AudioRaiseVolume" = "exec amixer -q set Master 5%+ unmute; notify-send 'Volume Increased'";
        "XF86AudioLowerVolume" = "exec amixer -q set Master 5%- unmute; notify-send 'Volume Decreased'";
        "XF86AudioMute" = "exec amixer -q set Master toggle; notify-send 'Mute Toggled'";
        "XF86MonBrightnessUp" = "exec sudo light -A 5; notify-send 'Brightness Increased'";
        "XF86MonBrightnessDown" = "exec sudo light -U 5; notify-send 'Brightness Decreased'";
      };
      startup = [
        { command = "kanshi"; }
        { command = "fcitx5 -rd"; }
      ];
      window = {
        commands = [
          { command = "floating enable, border normal"; criteria = { class = "mpv|Vlc"; }; }
          { command = "floating enable, resize set 800 600"; criteria = { class = "Gimp"; }; }
        ];
      };
      input = {
        "type:touchpad" = {
          tap = "enabled";
          natural_scroll = "enabled";
          dwt = "enabled";
        };
      };
    };
  };

  # Waybar Configuration (Linux)
  programs.waybar = lib.mkIf isLinux {
    enable = true;
    # Real configuration can be linked to arch/waybar.json later
    settings = {};
  };

  # Wofi Configuration (Linux)
  programs.wofi = lib.mkIf isLinux {
    enable = true;
    # Can link to specific dotfiles settings here later
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
