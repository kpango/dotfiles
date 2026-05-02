{ settings, ... }:

{
  # Audio (Pipewire setup)
  security.rtkit.enable = settings.desktop.audio.enable;
  services.pipewire = {
    enable = settings.desktop.audio.enable;
    alsa = {
      enable = settings.desktop.audio.enable;
      support32Bit = settings.desktop.audio.support32Bit;
    };
    pulse.enable = settings.desktop.audio.enable;
  };
}
