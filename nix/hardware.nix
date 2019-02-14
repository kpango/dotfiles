{ pkgs, lib, ... }:
{
  sound.enable = true;

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
    trackpoint.enable = true;
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
    opengl = {
      enable = true;
      driSupport = true;
      extraPackages = with pkgs;[ vaapiIntel ];
    };
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/1b93e06d-bbbc-4594-8d91-f29dafff109a";
    fsType = "xfs";
  };

  swapDevices = [
    {
      device = "/dev/disk/by-uuid/39e21160-19db-49d6-99e5-496ca3e69a8c";
    }
  ];

  powerManagement = {
    enable = true;
    cpuFreqGovernor = lib.mkDefault "powersave";
  };
}
