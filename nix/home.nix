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
    ghostty zsh helix tmux git go rustup ghq tig fd axel cmake jq k3d k9s kubectl lua gnumake pass procs ugrep wakeonlan wget

    # Extra Arch Linux dependencies explicitly requested
    alsa-utils ccache fastfetch fwupd gettext graphviz btop lsd lshw make mdadm mtr nmap ripgrep sed starship tar unzip bun

    # Sheldon plugin manager for Zsh
    sheldon
  ] ++ lib.optionals isDarwin [
    zed-editor colima docker
  ] ++ lib.optionals isLinux [
    sway swaybg swayidle waybar wl-clipboard wofi mako kanshi grim slurp light pavucontrol xfce.thunar noto-fonts-emoji
  ];

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
      core.excludesfile = "${../gitignore}";
    };

    # Append the raw gitconfig if necessary, or let Home Manager handle it.
    # To avoid clashes with native Home Manager git blocks, we use an include path:
    includes = [
      { path = "${../gitconfig}"; }
    ];
  };

  # Linux Sway Configuration (mapped from arch/sway.conf)
  wayland.windowManager.sway = lib.mkIf isLinux {
    enable = true;
    config = {
      modifier = "Mod4";
      terminal = "ghostty -e zsh -c 'tmux -S /tmp/tmux.sock -q has-session && exec tmux -S /tmp/tmux.sock -2 attach-session -d || exec tmux -S /tmp/tmux.sock -2 new-session -n$USER -s$USER@$(hostname)'";
      menu = "wofi --show drun -i";
      bars = [{ command = "waybar"; }];
      fonts = { names = [ "HackGen35ConsoleNF" ]; style = "Regular"; size = 16.0; };
      output = { "*" = { bg = "~/.wallpapers/default.png fill"; scale = "1.00"; }; };
      keybindings = lib.mkOptionDefault {
        "Mod4+Return" = "exec ghostty";
        "XF86AudioRaiseVolume" = "exec amixer -q set Master 5%+ unmute; notify-send 'Volume Increased'";
        "XF86AudioLowerVolume" = "exec amixer -q set Master 5%- unmute; notify-send 'Volume Decreased'";
        "XF86AudioMute" = "exec amixer -q set Master toggle; notify-send 'Mute Toggled'";
        "XF86MonBrightnessUp" = "exec sudo light -A 5; notify-send 'Brightness Increased'";
        "XF86MonBrightnessDown" = "exec sudo light -U 5; notify-send 'Brightness Decreased'";
      };
      startup = [ { command = "kanshi"; } { command = "fcitx5 -rd"; } ];
      window = {
        commands = [
          { command = "floating enable, border normal"; criteria = { class = "mpv|Vlc"; }; }
          { command = "floating enable, resize set 800 600"; criteria = { class = "Gimp"; }; }
        ];
      };
      input = { "type:touchpad" = { tap = "enabled"; natural_scroll = "enabled"; dwt = "enabled"; }; };
    };
  };

  programs.waybar = lib.mkIf isLinux { enable = true; };
  programs.wofi = lib.mkIf isLinux { enable = true; };
  programs.home-manager.enable = true;
}
