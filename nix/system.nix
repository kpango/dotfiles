{ config, pkgs, lib, ... }:
{

  fileSystems = {
    "/" = {
      label = "root";
      options = [ "noatime" "nodiratime" "discard" ];
    };
    "/boot".label = "boot";
  };

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
  };

  systemd = {
    tmpfiles.rules = let mqueue = "/proc/sys/fs/mqueue"; in [
      "w ${mqueue}/msgsize_max - - - - ${toString (64 * 1024)}"
      "w ${mqueue}/msg_max     - - - - 50"
    ];
    extraConfig = ''
      DefaultCPUAccounting=true
      DefaultBlockIOAccounting=true
      DefaultMemoryAccounting=true
      DefaultTasksAccounting=true
    '';
  };
}
