{ settings, ... }:

let
  audio = settings.desktop.audio;
in
{
  # Audio (Pipewire setup)
  security.rtkit.enable = audio.enable;
  services.pipewire = {
    enable = audio.enable;
    alsa = {
      enable = audio.enable;
      support32Bit = audio.support32Bit;
    };
    pulse.enable = audio.enable;
  };
}
