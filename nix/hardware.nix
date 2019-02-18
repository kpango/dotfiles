{ pkgs, lib, ... }:
{
  sound = {
    enable = true;
    mediaKeys.enable = true;
  };

  hardware = {
    pulseaudio = {
      enable = true;
      extraConfig = "load-module module-switch-on-connect";
      # extraModules = [ pkgs.pulseaudio-modules-bt ];
      package = pkgs.pulseaudioFull;
      support32Bit = true;
      tcp.anonymousClients.allowAll = true;
      tcp.enable = true;
      zeroconf.discovery.enable = true;
      zeroconf.publish.enable = true;
    };
    bluetooth = {
      enable = true;
      extraConfig = "
        [General]
        Enable=Source,Sink,Media,Socket
      ";
    };
    enableRedistributableFirmware = true;
    trackpoint = {
      enable = true;
      sensitivity = 255;
      speed = 200;
      emulateWheel = true;
    };
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
    opengl = {
      enable = true;
      driSupport = true;
      extraPackages = with pkgs;[ vaapiIntel ];
    };
  };

  powerManagement = {
    enable = true;
  };
}
