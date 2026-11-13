{
  lib,
  pkgs,
  isDarwin,
  dotfilesPath,
  ...
}:

let
  # pinentry-tmux (tmux.conf.d/pinentry-tmux, built+installed to
  # /usr/local/bin by `make pinentry/install`) is the same tmux-popup pinentry
  # Linux uses (linux.nix leaves gpg-agent.conf pointing at it unmodified). It
  # falls back to $PINENTRY_TMUX_FALLBACK when no tmux popup is reachable
  # (e.g. gpg invoked outside tmux); its own default (/usr/bin/pinentry-tty)
  # doesn't exist on macOS, so wrap it to fall back to the native
  # Keychain-integrated pinentry_mac instead. pinentry comes from nixpkgs, not
  # /opt/homebrew — pkgs.pinentry_mac exposes a bin/ wrapper around the .app
  # bundle, so getExe resolves to a real binary.
  pinentryTmuxDarwin = pkgs.writeShellScript "pinentry-tmux-darwin" ''
    export PINENTRY_TMUX_FALLBACK="${lib.getExe pkgs.pinentry_mac}"
    exec /usr/local/bin/pinentry-tmux "$@"
  '';
in
{
  home.file = lib.mkIf isDarwin {
    ".gnupg/gpg-agent.conf".text =
      builtins.replaceStrings [ "/usr/local/bin/pinentry-tmux" ] [ "${pinentryTmuxDarwin}" ]
        (builtins.readFile "${dotfilesPath}/gpg-agent.conf");
    # ".docker/config.json" (sourced from macos/docker_config.json) removed along with
    # colima/docker — apple/container doesn't read Docker's config.json at all (no
    # credsStore/credHelpers support; see modules/darwin/containerization.nix).

    # Two LaunchAgents from macos/ are deliberately not installed here:
    #
    #   localhost.homebrew-autoupdate.plist — Homebrew is disabled (see
    #     core/settings.nix); updates go through `make nix/update` + `nix-update`.
    #
    #   ulimit.plist — it declares Label "limit.maxfiles", the same label as the
    #     nix-darwin daemon in modules/darwin/system.nix, and a user LaunchAgent
    #     cannot raise the system file descriptor limit anyway. The daemon is the
    #     mechanism that actually works, so this would only add a label clash.
  };

  # pinentry_mac stays installed even though gpg-agent.conf no longer points
  # at it directly: pinentry-tmux-darwin (above) execs it as the fallback
  # pinentry when no tmux popup is reachable.
  home.packages = lib.mkIf isDarwin [ pkgs.pinentry_mac ];
}
