{ pkgs, lib, settings, ... }:

{
  # ────────────────────────────────────────────────
  # mdadm RAID0 on NVMe
  # /dev/md0 assembled from nvme*n*p* partitions
  # UUID from live system: 24419f2a:d88cf8d1:cb2b437a:96cbf870
  # ────────────────────────────────────────────────

  # initrd mdadm configuration (embedded into initramfs)
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      DEVICE partitions
      ARRAY /dev/md0 metadata=1.2 name=archiso:0 UUID=24419f2a:d88cf8d1:cb2b437a:96cbf870
    '';
  };

  # mdadm daemon for monitoring / mail alerts
  systemd.services.mdmonitor = {
    description = "MD RAID monitoring";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "forking";
      ExecStart = "${pkgs.mdadm}/bin/mdadm --monitor --scan --daemonise --delay=60";
      PIDFile = "/run/mdadm/monitor.pid";
    };
  };

  # ────────────────────────────────────────────────
  # Root filesystem (XFS on md0)
  # ────────────────────────────────────────────────
  fileSystems."/" = {
    device = "/dev/md0";
    fsType = "xfs";
    options = settings.system.disks.rootOptions;
  };

  # ────────────────────────────────────────────────
  # EFI system partition
  # ────────────────────────────────────────────────
  fileSystems."/boot" = {
    device = "PARTUUID=713a6825-7f30-4dc1-9515-aa15b9057fc0";
    fsType = "vfat";
    options = settings.system.disks.bootOptions;
  };

  # ────────────────────────────────────────────────
  # Swap — nvme1n1p1 partition
  # ────────────────────────────────────────────────
  swapDevices = [
    { device = "/dev/nvme1n1p1"; }
  ];

  # Resume from this swap device (hibernate)
  boot.resumeDevice = "/dev/nvme1n1p1";

  # ────────────────────────────────────────────────
  # Supported filesystems
  # ────────────────────────────────────────────────
  boot.supportedFilesystems = [ "xfs" "vfat" "ext4" ];
}
