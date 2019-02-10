{ config, pkgs, lib, ... }:
{
  fileSystems."/".label = "root";
  fileSystems."/boot".label = "boot";

  time.timeZone = "Asia/Tokyo";

  security.sudo.enable = true;

  system = {
    stateVersion = "18.09"; # Did you read the comment?
    autoUpgrade = {
      enable = true;
      flags = lib.mkForce
        [
          "--fast"
          "--no-build-output"
          "-I" "nixpkgs=/etc/nixos/nixpkgs-channels"
        ];
    };
    services = {
      nixos-upgrade = {
        path = [ pkgs.git  ];
        preStart = ''
            if [ ! -e /etc/nixos/nixpkgs-channels  ]; then
              cd /etc/nixos
              git clone git://github.com/NixOS/nixpkgs-channels.git -b nixos-${nixosVersion}
            fi
            cd /etc/nixos/nixpkgs-channels
            git pull
            if [ -e /etc/nixos/dotfiles  ]; then
              cd /etc/nixos/dotfiles
              git pull
            fi
          '';
      };
    };
  extraConfig = ''
      DefaultCPUAccounting=true
      DefaultBlockIOAccounting=true
      DefaultMemoryAccounting=true
      DefaultTasksAccounting=true
    '';
  };
}
