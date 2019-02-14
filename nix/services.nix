{ pkgs, ... }:
{
  services = {
    timesyncd.enable = true;
    # nixosManual.showManual = true;
    dbus = {
      enable = true;
      socketActivated = true;
    }
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
