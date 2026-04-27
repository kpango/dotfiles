{ settings, ... }:

{
  # Homebrew configuration
  homebrew = {
    enable = settings.darwin.homebrew.enable;
    onActivation = {
      autoUpdate = settings.darwin.homebrew.autoUpdate;
      upgrade = settings.darwin.homebrew.upgrade;
      cleanup = settings.darwin.homebrew.cleanup;
    };
    taps = settings.darwin.homebrew.taps;
    brews = [
      # CLI tools are handled by home-manager, but brew-specific formulas can go here
    ];
    casks = settings.darwin.homebrew.casks;
    masApps = settings.darwin.masApps;
  };
}