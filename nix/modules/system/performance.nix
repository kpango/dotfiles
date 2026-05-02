{ pkgs, lib, ... }:

{
  # ────────────────────────────────────────────────
  # CPU governor: performance for all cores
  # Threadripper 3990X — 64 cores / 128 threads
  # amd_pstate=disable means the legacy acpi-cpufreq driver
  # controls frequency; governor must be set explicitly.
  # ────────────────────────────────────────────────
  systemd.services."cpu-performance" = {
    description = "Set CPU frequency governor to performance";
    documentation = [ "https://www.kernel.org/doc/html/latest/admin-guide/pm/cpufreq.html" ];
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "set-cpu-perf" ''
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          [ -f "$f" ] && echo performance > "$f"
        done
      '';
    };
  };

  # ────────────────────────────────────────────────
  # KSM — Kernel Same-page Merging
  # Useful on a 251 GB machine running many containers/VMs
  # ────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/ksm/run              - - - - 1"
    "w /sys/kernel/mm/ksm/sleep_millisecs  - - - - 200"
    "w /sys/kernel/mm/ksm/pages_to_scan   - - - - 1024"

    # Transparent Huge Pages: madvise (let processes opt in)
    "w /sys/kernel/mm/transparent_hugepage/enabled                        - - - - madvise"
    "w /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs - - - - 1000"
  ];

  # ────────────────────────────────────────────────
  # journald limits — prevent log floods filling RAM
  # ────────────────────────────────────────────────
  services.journald.extraConfig = ''
    SystemMaxUse=512M
    SystemMaxFileSize=64M
    RuntimeMaxUse=128M
    Compress=yes
    RateLimitInterval=30s
    RateLimitBurst=10000
  '';

  # ────────────────────────────────────────────────
  # irqbalance — distribute IRQs across all 128 threads.
  # Exclude NVMe from balancing: NVMe controllers handle their own
  # IRQ affinity via io_uring / blk-mq and irqbalance moving them
  # causes latency spikes (matches Arch irqbalance.service drop-in).
  # ────────────────────────────────────────────────
  services.irqbalance.enable = true;
  systemd.services.irqbalance.serviceConfig.ExecStart = lib.mkForce
    "${pkgs.irqbalance}/sbin/irqbalance --foreground --banmod=nvme";

  # ────────────────────────────────────────────────
  # Security / PAM limits
  # ────────────────────────────────────────────────
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "524288"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "524288"; }
    { domain = "*"; type = "soft"; item = "memlock"; value = "unlimited"; }
    { domain = "*"; type = "hard"; item = "memlock"; value = "unlimited"; }
    { domain = "*"; type = "soft"; item = "nproc"; value = "unlimited"; }
    { domain = "*"; type = "hard"; item = "nproc"; value = "unlimited"; }
  ];

  # ────────────────────────────────────────────────
  # fstrim — weekly TRIM for NVMe longevity
  # ────────────────────────────────────────────────
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };
}
