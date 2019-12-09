{ config, pkgs, lib, ... }:
{
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/root";
      fsType = "xfs";
      options = [ "noatime" "nodiratime" "discard" ];
      label = "root";
    };
    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
      label = "boot";
    };
    # "/" = {
    #   label = "root";
    #   options = [ "noatime" "nodiratime" "discard" ];
    # };
    # "/boot".label = "boot";
  };

  time = {
    hardwareClockInLocalTime = true;
    timeZone = "Asia/Tokyo";
  };

  system = {
    stateVersion = "19.03"; # Did you read the comment?
    autoUpgrade = {
      enable = true;
      flags = lib.mkForce
        [
          "--fast"
          "--max-jobs"
          "4"
          "--no-build-output"
          "-I" "nixpkgs=/etc/nixos/nixpkgs-channels"
        ];
    };
  };

  systemd = {
    services = {
      nixos-upgrade = {
        script = pkgs.lib.mkForce ''
          ${pkgs.nix}/bin/nix-channel --update nixos-unstable
          ${config.system.build.nixos-rebuild}/bin/nixos-rebuild boot --upgrade ${toString config.system.autoUpgrade.flags}
        '';
      };
      cpu-throttling = {
        enable = true;
        description = "Set temp offset to 3°C, so the new trip point is 97°C";
        documentation = [
          "https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Power_management.2FThrottling_issues"
        ];
        path = [ pkgs.msr-tools ];
        script = "wrmsr -a 0x1a2 0x3000000";
        serviceConfig = {
          Type = "oneshot";
        };
        wantedBy = [ "timers.target" ];
      };
    };
    timers.cpu-throttling = {
      enable = true;
      description = "Set cpu throttling threshold to 97°C";
      documentation = [
        "https://wiki.archlinux.org/index.php/Lenovo_ThinkPad_X1_Carbon_(Gen_6)#Power_management.2FThrottling_issues"
      ];
      timerConfig = {
        OnActiveSec = 60;
        OnUnitActiveSec = 60;
        Unit = "cpu-throttling.service";
      };
      wantedBy = [ "timers.target" ];
    };
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
