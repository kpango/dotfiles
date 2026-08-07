{
  lib,
  pkgs,
  isDarwin,
  dotfilesPath,
  ...
}:

{
  home.file = lib.mkIf isDarwin {
    # pinentry comes from nixpkgs, not /opt/homebrew — pkgs.pinentry_mac exposes
    # a bin/ wrapper around the .app bundle, so getExe resolves to a real binary.
    ".gnupg/gpg-agent.conf".text =
      builtins.replaceStrings [ "/usr/local/bin/pinentry-tmux" ] [ "${lib.getExe pkgs.pinentry_mac}" ]
        (builtins.readFile "${dotfilesPath}/gpg-agent.conf");
    ".docker/config.json".source = "${dotfilesPath}/macos/docker_config.json";

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

  home.packages = lib.mkIf isDarwin [ pkgs.pinentry_mac ];
}
