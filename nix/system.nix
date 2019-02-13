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
  # extraConfig = ''
  #     DefaultCPUAccounting=true
  #     DefaultBlockIOAccounting=true
  #     DefaultMemoryAccounting=true
  #     DefaultTasksAccounting=true
  #   '';
  };
}
