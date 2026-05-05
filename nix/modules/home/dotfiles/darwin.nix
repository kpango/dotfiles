{ lib, isDarwin, dotfilesPath, ... }:

{
  home.file = lib.mkIf isDarwin {
    ".gnupg/gpg-agent.conf".text = builtins.replaceStrings
      [ "/usr/bin/pinentry-tty" ]
      [ "/opt/homebrew/bin/pinentry-mac" ]
      (builtins.readFile "${dotfilesPath}/gpg-agent.conf");
    ".docker/config.json".source = "${dotfilesPath}/macos/docker_config.json";

    "Library/LaunchAgents/localhost.homebrew-autoupdate.plist".source = "${dotfilesPath}/macos/localhost.homebrew-autoupdate.plist";
    "Library/LaunchAgents/ulimit.plist".source = "${dotfilesPath}/macos/ulimit.plist";
  };
}
