{
  lib,
  hostname,
  isLinux,
  dotfilesPath,
  ...
}:

{
  home.file = lib.mkIf isLinux {
    ".gnupg/gpg-agent.conf".source = "${dotfilesPath}/gpg-agent.conf";
    ".docker/config.json".source = "${dotfilesPath}/dockers/config.json";

    ".config/mako/config".source = "${dotfilesPath}/arch/mako.conf";
    ".config/kanshi/config".source = "${dotfilesPath}/arch/kanshi.conf";
    ".config/workstyle/config.toml".source = "${dotfilesPath}/arch/workstyle.toml";
    ".config/waybar/config".source = "${dotfilesPath}/arch/waybar.json";
    ".config/waybar/style.css".source =
      if hostname == "thinkpad-p1-gen5" then
        "${dotfilesPath}/arch/waybar_p1.css"
      else
        "${dotfilesPath}/arch/waybar.css";
    # arch/sway.conf is the self-contained top-level config, matching the
    # `arch/sway.conf -> .config/sway/config` mapping in Makefile.d/install.mk.
    # (The previous arch/sway/config, arch/sway/config.d and arch/sway/scripts
    # paths do not exist in this repo — arch/sway/ holds only cheatsheet.md, and
    # config.d/ and scripts/ live at the repository root.)
    ".config/sway/config".source = "${dotfilesPath}/arch/sway.conf";
    ".config/sway/scripts".source = "${dotfilesPath}/sway/scripts";
    # Installed for parity with the repo layout; note that arch/sway.conf does
    # not `include` these yet, so they are inert until it does.
    ".config/sway/config.d".source = "${dotfilesPath}/sway/config.d";
    ".config/sway/cheatsheet.md".source = "${dotfilesPath}/arch/sway/cheatsheet.md";
    ".Xdefaults".source = "${dotfilesPath}/arch/Xdefaults";
    ".config/wofi/config".source = "${dotfilesPath}/arch/wofi/wofi.conf";
    ".config/wofi/style.css".source = "${dotfilesPath}/arch/wofi/style.css";
    # ranger's config moved to dotfiles/shared.nix — it isn't Wayland-specific
    # like everything else in this block, so darwin gets it too now.
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
