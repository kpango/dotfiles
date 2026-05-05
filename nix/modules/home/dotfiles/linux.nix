{ lib, hostname, isLinux, dotfilesPath, ... }:

{
  home.file = lib.mkIf isLinux {
    ".gnupg/gpg-agent.conf".source = "${dotfilesPath}/gpg-agent.conf";
    ".docker/config.json".source = "${dotfilesPath}/dockers/config.json";

    ".config/mako/config".source = "${dotfilesPath}/arch/mako.conf";
    ".config/kanshi/config".source = "${dotfilesPath}/arch/kanshi.conf";
    ".config/workstyle/config.toml".source = "${dotfilesPath}/arch/workstyle.toml";
    ".config/waybar/config".source = "${dotfilesPath}/arch/waybar.json";
    ".config/waybar/style.css".source =
      if hostname == "thinkpad-p1-gen5"
      then "${dotfilesPath}/arch/waybar_p1.css"
      else "${dotfilesPath}/arch/waybar.css";
    # arch/sway/config is the top-level entry point; it includes config.d/* and sway.conf
    ".config/sway/config".source = "${dotfilesPath}/arch/sway/config";
    ".config/sway/sway.conf".source = "${dotfilesPath}/arch/sway.conf";
    ".config/sway/config.d".source = "${dotfilesPath}/arch/sway/config.d";
    ".config/sway/scripts".source = "${dotfilesPath}/arch/sway/scripts";
    ".config/sway/cheatsheet.md".source = "${dotfilesPath}/arch/sway/cheatsheet.md";
    ".Xdefaults".source = "${dotfilesPath}/arch/Xdefaults";
    ".config/wofi/config".source = "${dotfilesPath}/arch/wofi/wofi.conf";
    ".config/wofi/style.css".source = "${dotfilesPath}/arch/wofi/style.css";
    ".config/ranger".source = "${dotfilesPath}/arch/ranger";
    ".config/fcitx5/conf/classicui.conf".source = "${dotfilesPath}/arch/fcitx.classicui.conf";
    ".config/fcitx5/config".source = "${dotfilesPath}/arch/fcitx.conf";
    ".config/fcitx5/profile".source = "${dotfilesPath}/arch/fcitx.profile";
    ".Xmodmap".source = "${dotfilesPath}/arch/Xmodmap";
  };

  # Source Linux env bash profile
  programs.bash.initExtra = lib.mkIf isLinux ''
    source ${dotfilesPath}/arch/environment
  '';
}
