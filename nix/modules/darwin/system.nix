{ versions, settings, ... }:

{
  # To avoid path errors, use the recommended nix settings in macOS
  nix.useDaemon = true;
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