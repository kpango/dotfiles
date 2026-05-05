{ versions, settings, username, ... }:

{
  # Required by nix-darwin for user-scoped options (homebrew, defaults, etc.)
  system.primaryUser = username;

  nix.enable = true;

  # Launchd daemon to raise file descriptor limits
  launchd.daemons.limit-maxfiles = {
    serviceConfig = {
      Label = "limit.maxfiles";
      ProgramArguments = [
        "launchctl"
        "limit"
        "maxfiles"
        "${toString settings.system.fileDescriptorLimit}"
        "${toString settings.system.fileDescriptorLimit}"
      ];
      RunAtLoad = true;
      ServiceIPC = false;
    };
  };

  system.stateVersion = versions.darwin;
}
