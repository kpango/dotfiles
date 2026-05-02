{ lib, isDarwin, dotfilesPath, ... }:

{
  home.file = lib.mkIf isDarwin {
    ".gnupg/gpg-agent.conf".text = builtins.replaceStrings
      [ "/usr/bin/pinentry-tty" ]
      [ "/opt/homebrew/bin/pinentry-mac" ]
      (builtins.readFile ../../../../gpg-agent.conf);
    ".docker/config.json".source = ../../../../macos/docker_config.json;

    "Library/LaunchAgents/localhost.homebrew-autoupdate.plist".source = ../../../../macos/localhost.homebrew-autoupdate.plist;
    "Library/LaunchAgents/ulimit.plist".source = ../../../../macos/ulimit.plist;
  };
}
