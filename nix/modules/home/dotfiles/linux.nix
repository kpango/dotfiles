{ lib, hostname, isLinux, dotfilesPath, ... }:

{
  home.file = lib.mkIf isLinux {
    ".gnupg/gpg-agent.conf".source = ../../../../gpg-agent.conf;
    ".docker/config.json".source = ../../../../dockers/config.json;

    ".config/mako/config".source = ../../../../arch/mako.conf;
    ".config/kanshi/config".source = ../../../../arch/kanshi.conf;
    ".config/workstyle/config.toml".source = ../../../../arch/workstyle.toml;
    ".config/waybar/config".source = ../../../../arch/waybar.json;
    ".config/waybar/style.css".source = if hostname == "thinkpad-p1-gen5" then ../../../../arch/waybar_p1.css else ../../../../arch/waybar.css;
    # arch/sway/config is the top-level entry point; it includes config.d/* and sway.conf
    ".config/sway/config".source = ../../../../arch/sway/config;
    ".config/sway/sway.conf".source = ../../../../arch/sway.conf;
    ".config/sway/config.d".source = ../../../../arch/sway/config.d;
    ".config/sway/scripts".source = ../../../../arch/sway/scripts;
    ".config/sway/cheatsheet.md".source = ../../../../arch/sway/cheatsheet.md;
    ".Xdefaults".source = ../../../../arch/Xdefaults;
    ".config/wofi/config".source = ../../../../arch/wofi/wofi.conf;
    ".config/wofi/style.css".source = ../../../../arch/wofi/style.css;
    ".config/ranger".source = ../../../../arch/ranger;
    ".config/fcitx5/conf/classicui.conf".source = ../../../../arch/fcitx.classicui.conf;
    ".config/fcitx5/config".source = ../../../../arch/fcitx.conf;
    ".config/fcitx5/profile".source = ../../../../arch/fcitx.profile;
    ".config/psd/psd.conf".source = ../../../../arch/psd.conf;
    ".Xmodmap".source = ../../../../arch/Xmodmap;
  };

  # Source Linux env bash profile
  programs.bash.initExtra = lib.mkIf isLinux ''
    source ${dotfilesPath}/arch/environment
  '';
}
