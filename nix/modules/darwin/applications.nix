{ pkgs, ... }:

{
  # GUI applications, formerly Homebrew casks (see core/settings.nix).
  #
  # These belong in environment.systemPackages rather than home.packages so that
  # nix-darwin's `system.activationScripts.applications` picks them up: it rsyncs
  # the .app bundles into "/Applications/Nix Apps" as real directories (not
  # symlinks), which is what makes them visible to Spotlight and Launchpad.
  #
  # cask -> nixpkgs mapping:
  #   ghostty             -> ghostty-bin   (`ghostty` itself is platforms.linux)
  #   google-chrome       -> google-chrome
  #   slack               -> slack
  #   zoom                -> zoom-us
  #   discord             -> discord
  #   visual-studio-code  -> vscode
  #   tailscale           -> tailscale     (CLI + tailscaled only; the macOS GUI
  #                                         and its Network Extension are not
  #                                         packaged, so this runs in userspace
  #                                         networking mode)
  #   font-hackgen-nerd   -> hackgen-nf-font, already installed by
  #                          core/common.nix via fonts.packages
  #
  # alacritty was only ever declared for Linux (packages/linux.nix, as a plain
  # home.packages entry — Linux has no equivalent of this "rsync into
  # /Applications" step). It builds fine for aarch64-darwin and produces a
  # real .app bundle there, so it belongs here instead, next to the other GUI
  # apps, for Spotlight/Launchpad to see it.
  #
  # These apps self-update on macOS, but /nix/store is read-only, so their
  # updaters will fail. Updates come from `make nix/update` + `nix-update`.
  environment.systemPackages = with pkgs; [
    alacritty
    discord
    ghostty-bin
    google-chrome
    slack
    tailscale
    vscode
    zoom-us
  ];
}
