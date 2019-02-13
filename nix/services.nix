{ pkgs, ... }:
{
  services = {
    timesyncd.enable = true;
    # nixosManual.showManual = true;
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
    # nixos-upgrade = {
    #   path = [ pkgs.git ];
    #   preStart = ''
    #       if [ ! -e /etc/nixos/nixpkgs-channels  ]; then
    #         cd /etc/nixos
    #         # git clone git://github.com/NixOS/nixpkgs-channels.git -b nixos-${nixosVersion}
    #         git clone git://github.com/NixOS/nixpkgs-channels.git -b nixos-18.09
    #       fi
    #       cd /etc/nixos/nixpkgs-channels
    #       git pull
    #       if [ -e /etc/nixos/dotfiles  ]; then
    #         cd /etc/nixos/dotfiles
    #         git pull
    #       fi
    #     '';
    # };
  };
}
