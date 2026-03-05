{ config, pkgs, lib, username, versions, ... }:

{
  imports = [
    ../core/common.nix
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
    if builtins.pathExists ../modules/macos.nix then
      import ../modules/macos.nix
    else
      { };

  # Native nix-darwin system.defaults for Dock
  system.defaults.dock = {
    autohide = true;
    largesize = 68;
    launchanim = true;
    mineffect = "genie";
    show-recents = false;
    wvous-br-corner = 14; # 14 = Put Display to Sleep
  };

  # Finder settings
  system.defaults.finder = {
    ShowExternalHardDrivesOnDesktop = true;
    ShowHardDrivesOnDesktop = false;
    ShowRemovableMediaOnDesktop = true;
    _FXSortFoldersFirst = true;
  };

  # Global macOS preferences
  system.defaults.NSGlobalDomain = {
    AppleInterfaceStyle = "Dark";
    "com.apple.sound.beep.flash" = false;
    "com.apple.sound.uiaudio.enabled" = false;
    "com.apple.springing.delay" = 0.5;
    "com.apple.springing.enabled" = true;
    "com.apple.trackpad.forceClick" = true;
  };

  # Screenshot settings
  system.defaults.screencapture = {
    type = "png";
  };

  # Trackpad settings
  system.defaults.trackpad = {
    TrackpadRightClick = true;
    TrackpadThreeFingerDrag = false;
  };

  # Spaces settings
  system.defaults.spaces.spans-displays = false;

  # Homebrew integration for GUI apps (casks) from Brewfile
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
    };
    taps = [
      "homebrew/autoupdate"
      "homebrew/bundle"
    ];
    casks = [
      "discord"
      "font-hackgen-nerd"
      "google-chrome"
      "google-japanese-ime"
      "messenger"
      "slack"
      "visual-studio-code"
      "zoom"
    ];
  };

  # Launchd daemon to raise file descriptor limits (from macos/ulimit.plist)
  launchd.daemons.limit-maxfiles = {
    serviceConfig = {
      Label = "limit.maxfiles";
      # Set soft and hard limits for maximum open file descriptors to 524288
      ProgramArguments = [
        "launchctl"
        "limit"
        "maxfiles"
        "524288"
        "524288"
      ];
      RunAtLoad = true;
      ServiceIPC = false;
    };
  };

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = versions.darwin;
}
