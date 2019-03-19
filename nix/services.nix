{ pkgs, ... }:
{
  services = {
    timesyncd = {
      enable = true;
    };
    dbus = {
      enable = true;
      socketActivated = true;
    };
    locate = {
      enable = true;
    };
    nixosManual = {
      showManual = true;
    };
    ntp = {
      enable = true;
    };
    openssh = {
      enable = true;
      passwordAuthentication = false;
      permitRootLogin = "no";
      extraConfig = ''
        StreamLocalBindUnlink yes
      '';
    };
    tlp = {
      enable = true;
    };
    upower = {
      enable = true;
    };
    sshd = {
      enable = true;
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
        cups-bjnp
      ];
    };
  };
}
