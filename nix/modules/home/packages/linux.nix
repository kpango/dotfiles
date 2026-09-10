{
  pkgs,
  lib,
  isLinux,
  ...
}:

{
  # alacritty and sysbench moved out: both build fine for aarch64-darwin and
  # have nothing Linux-specific about them (unlike everything left below,
  # which is ALSA/PipeWire/Wayland/X11-tied or Linux-WM-IPC-tied). alacritty
  # is a GUI app, so its darwin home goes through applications.nix
  # (environment.systemPackages) rather than home.packages — see the comment
  # there. sysbench went to packages/shared.nix.
  #
  # discord/ghostty/slack/zoom-us are also already covered for darwin via
  # modules/darwin/applications.nix (as discord/ghostty-bin/slack/zoom-us).
  #
  # workstyle builds for aarch64-darwin per nixpkgs meta.platforms, but it
  # renames workspaces by querying Sway/i3/Hyprland's IPC socket — there is no
  # macOS window manager it can talk to, so shipping the binary would be dead
  # weight, not a working feature. Not added.
  home.packages = lib.mkIf isLinux (
    with pkgs;
    [
      alsa-utils
      brightnessctl
      discord
      ghostty
      crosspipe
      # arch/pkg.list and arch/pkg_p1.list both install this; kept Linux-only
      # (rather than shared.nix) since it has no confirmed darwin use here.
      mpv
      pavucontrol
      # dockers/base.Dockerfile apt-installs pinentry-tty for GPG TTY prompts
      # (zsh/20-ssh-gpg.zsh wires gpg-agent's pinentry to the tmux TTY).
      # darwin already gets pinentry_mac via dotfiles/darwin.nix.
      pinentry-tty
      slack
      workstyle
      thunar
      zoom-us
    ]
  );
}
