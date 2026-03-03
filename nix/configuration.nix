{ config, pkgs, lib, username, ... }:

{
  imports = [
    ./common.nix
  ];

  # To avoid path errors, use the recommended nix settings in macOS
  nix.useDaemon = true;

  # Tailscale background service enabling requires manual starting on macos,
  # but putting it in environment.systemPackages makes the binary available.
  # Note: macOS systemd equivalents (launchd) for tailscaled can be complex to setup via nix-darwin,
  # but tailscale CLI availability is guaranteed by the above.

  # Load dynamically extracted macOS defaults via defaults2nix safely
  # This uses builtins.pathExists to prevent evaluation errors if the file doesn't exist yet
  system.defaults.CustomUserPreferences =
    if builtins.pathExists ./macos.nix then
      import ./macos.nix
    else
      { };

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
