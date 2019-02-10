{ pkgs, ... }:
{
  hardware = {
    pulseaudio = {
      enable = true;
      extraConfig = "load-module module-switch-on-connect";
      extraModules = [ pkgs.pulseaudio-modules-bt ];
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
    cpu.intel.updateMicrocode = true;
    enableAllFirmware = true;
    opengl = {
      enable = true;
      driSupport = true;
    };
  };
  powerManagement = {
    enable = true;
    cpuFreqGovernor = lib.mkDefault "powersave";
  };

  services = {
    timesyncd.enable = true;
    nixosManual.showManual = true;
    dbus.enable = true;
    locate.enable = true;
    nixosManual.showManual = true;
    openssh = {
      enable = true;
      passwordAuthentication = false;
      permitRootLogin = "no";
      extraConfig = ''
        StreamLocalBindUnlink yes
      '';
    };
    unifi = {
      unifiPackage = pkgs.unifiTesting;
      enable = true;
    };
    printing = {
      enable = true;
      drivers = with pkgs; [
        gutenprint
        gutenprintBin
        hplip
        hplipWithPlugin
      ];
    };
  };
}
