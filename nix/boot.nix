{ config, pkgs, ... }:
{
  # Use the systemd-boot EFI boot loader.
  boot = {
    kernelModules = [ "kvm-intel" ];
    blacklistedKernelModules = [ "snd_pcsp" "pcspkr" ];
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "psmouse.synaptics_intertouch=1"
      "psmouse.proto=imps"
      "acpi.ec_no_wakeup=1"
      "intel_pstate=no_hwp"
    ];
    plymouth.enable = true;
    # supportedFilesystems = [ "xfs" "zfs" ];
    supportedFilesystems = [ "xfs" ];
    kernel = {
      sysctl = {
        "kernel.panic" = 30;
        "kernel.perf_event_paranoid" = 0;
        "net.core.netdev_max_backlog" = 4096;
        "net.core.optmem_max" = 40960;
        "net.core.rmem_default" = 16777216;
        "net.core.rmem_max" = 16777216;
        "net.core.somaxconn" = 4096;
        "net.core.wmem_default" = 16777216;
        "net.core.wmem_max" = 16777216;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_source_route" = 0;
        "net.ipv4.conf.lo.accept_redirects" = 0;
        "net.ipv4.conf.lo.accept_source_route" = 0;
        "net.ipv4.conf.wlp4s0.accept_redirects" = 0;
        "net.ipv4.conf.wlp4s0.accept_source_route" = 0;
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
        "net.ipv4.ip_local_port_range" = "1024 65535";
        "net.ipv4.tcp_abort_on_overflow" = 1;
        "net.ipv4.tcp_ecn" = 1;
        "net.ipv4.tcp_fack" = 1;
        "net.ipv4.tcp_fastopen" = 3;
        "net.ipv4.tcp_fin_timeout" = 30;
        "net.ipv4.tcp_keepalive_intvl" = 5;
        "net.ipv4.tcp_keepalive_probes" = 4;
        "net.ipv4.tcp_keepalive_time" = 20;
        "net.ipv4.tcp_low_latency" = 0;
        "net.ipv4.tcp_max_syn_backlog" = 4096;
        "net.ipv4.tcp_moderate_rcvbuf" = 1;
        "net.ipv4.tcp_no_metrics_save" = 1;
        "net.ipv4.tcp_orphan_retries" = 3;
        "net.ipv4.tcp_rfc1337" = 1;
        "net.ipv4.tcp_rmem" = "4096 87380 16777216";
        "net.ipv4.tcp_sack" = 1;
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.tcp_timestamps" = 0;
        "net.ipv4.tcp_tw_reuse" = 1;
        "net.ipv4.tcp_window_scaling" = 1;
        "net.ipv4.tcp_wmem" = "4096 87380 16777216";
        "vm.max_map_count" = 117715;
        "vm.overcommit_memory" = 2;
        "vm.overcommit_ratio" = 99;
        "vm.panic_on_oom" = 1;
        "vm.swappiness" = 1;
      };
    };
    loader = {
      systemd-boot.enable = true;
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };
    initrd = {
      availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
      kernelModules = [
        "kvm_intel"
        "tp_smapi"
        "dm_mod"
        "dm-crypt"
        "ext4"
        "ecb"
      ];
      luks.devices = [
        {
          name = "root";
          device = "/dev/nvme0n1p2";
          preLVM = true;
          allowDiscards = true;
        }
      ];
    };
  };
}
