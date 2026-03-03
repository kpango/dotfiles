{ config, pkgs, lib, username, ... }:

{
  # Nix settings and features
  nix.settings.experimental-features = "nix-command flakes";
  # To avoid path errors, use the recommended nix settings in macOS
  nix.useDaemon = true;

  # OS Level Tools & Services
  environment.systemPackages = with pkgs; [
    tailscale # System-level CLI version
  ];

  # Tailscale background service enabling requires manual starting on macos,
  # but putting it in environment.systemPackages makes the binary available.
  # Note: macOS systemd equivalents (launchd) for tailscaled can be complex to setup via nix-darwin,
  # but tailscale CLI availability is guaranteed by the above.

  # Fonts (installing at the OS level)
  fonts.packages = with pkgs; [
    hackgen-nf-font
  ];

  # Ensure the zsh shell is properly enabled at OS level (preventing Nix path issues)
  programs.zsh.enable = true;

  # User definitions (required to set the home directory correctly to prevent permission errors)
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
  };

  # Load dynamically extracted macOS defaults via defaults2nix safely
  # This uses builtins.pathExists to prevent evaluation errors if the file doesn't exist yet
  system.defaults.CustomUserPreferences =
    if builtins.pathExists ./all-defaults.nix
    then import ./all-defaults.nix
    else {};

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
