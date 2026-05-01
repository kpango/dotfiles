{ pkgs, lib, ... }:

{
  # ────────────────────────────────────────────────
  # Hostname (overridden by host-specific config)
  # ────────────────────────────────────────────────
  networking.hostName = lib.mkDefault "desk-threadripper";

  # ────────────────────────────────────────────────
  # Use predictable names disabled — we rely on udev
  # rules (70-persistent-network.rules) to assign
  # eth0 / sfp0 / sfp1 by MAC address.
  # ────────────────────────────────────────────────
  networking.usePredictableInterfaceNames = false;

  # ────────────────────────────────────────────────
  # systemd-networkd manages bonding + sfp slaves.
  # NetworkManager handles eth0 (backup/DHCP) and
  # is told to ignore the bond members.
  # ────────────────────────────────────────────────
  systemd.network.enable = true;
  networking.useNetworkd = true;

  # NetworkManager for eth0 only; bond stack is networkd-managed.
  networking.networkmanager = {
    enable = true;
    dns = "dnsmasq";
    unmanaged = [
      "interface-name:sfp0"
      "interface-name:sfp1"
      "interface-name:bond0"
    ];
  };

  # ────────────────────────────────────────────────
  # Bond master: 802.3ad LACP
  # ────────────────────────────────────────────────
  systemd.network.netdevs."10-bond0" = {
    netdevConfig = {
      Name = "bond0";
      Kind = "bond";
    };
    bondConfig = {
      Mode = "802.3ad";
      TransmitHashPolicy = "encap3+4";
      MIIMonitorSec = "100ms";
      LACPTransmitRate = "fast";
      AdSelect = "stable";
      MinLinks = 1;
      AllSlavesActive = true;
      UpDelaySec = "0ms";
      DownDelaySec = "0ms";
      ResendIGMP = 1;
    };
  };

  # bond0 network: static IP, MTU 9000
  systemd.network.networks."10-bond0" = {
    matchConfig.Name = "bond0";
    networkConfig = {
      Address = "10.0.0.40/24";
      Gateway = "10.0.0.1";
      DNS = [ "1.1.1.1" "8.8.8.8" "1.0.0.1" "8.8.4.4" ];
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      DHCP = "no";
    };
    linkConfig = {
      MTUBytes = "9000";
      # Randomised MAC for bond0 (matching nm bond0 cloned-mac)
      MACAddress = "1a:fd:3d:9c:b0:4d";
    };
    routingPolicyRules = [ ];
  };

  # ────────────────────────────────────────────────
  # Bond slave: sfp0 (X710, MAC 64:9D:99:B1:03:44)
  # ────────────────────────────────────────────────
  systemd.network.networks."11-sfp0" = {
    matchConfig = {
      Name = "sfp0";
      MACAddress = "64:9D:99:B1:03:44";
    };
    networkConfig.Bond = "bond0";
    linkConfig = {
      MTUBytes = "9000";
      # Ring buffers & offloads are handled by the x710-tuning service
    };
    bondPortConfig = { };
  };

  # ────────────────────────────────────────────────
  # Bond slave: sfp1 (X710, MAC 64:9D:99:B1:03:45)
  # ────────────────────────────────────────────────
  systemd.network.networks."11-sfp1" = {
    matchConfig = {
      Name = "sfp1";
      MACAddress = "64:9D:99:B1:03:45";
    };
    networkConfig.Bond = "bond0";
    linkConfig.MTUBytes = "9000";
    bondPortConfig = { };
  };

  # ────────────────────────────────────────────────
  # eth0 backup (Intel I211 1GbE, F0:2F:74:D4:37:35)
  # Low autoconnect priority; DHCP fallback.
  # ────────────────────────────────────────────────
  systemd.network.networks."50-eth0" = {
    matchConfig = {
      Name = "eth0";
      MACAddress = "F0:2F:74:D4:37:35";
    };
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    dhcpV4Config.RouteMetric = 999;
  };

  # ────────────────────────────────────────────────
  # DNS / Nameservers
  # ────────────────────────────────────────────────
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
    "1.0.0.1"
    "8.8.4.4"
  ];

  # ────────────────────────────────────────────────
  # Firewall
  # ────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    allowPing = true;
    checkReversePath = false;
    allowedTCPPorts = [ 22 80 443 3000 8000 8080 8443 9999 27036 27037 ];
    allowedUDPPorts = [ 27031 27037 ];
    allowedUDPPortRanges = [{ from = 60000; to = 61000; }];
    # Allow all traffic on Docker / container bridges
    extraCommands = ''
      iptables -I INPUT -i bond0 -j ACCEPT || true
      iptables -I FORWARD -i docker0 -j ACCEPT || true
      iptables -I FORWARD -o docker0 -j ACCEPT || true
      iptables -I INPUT -p udp -m udp --dport 32768:60999 -j ACCEPT || true
    '';
  };

  # ────────────────────────────────────────────────
  # Kernel sysctl — full tuning from tr-sysctl.conf
  # ────────────────────────────────────────────────
  boot.kernel.sysctl = {
    # Kernel hardening / tuning
    "kernel.kptr_restrict"            = 1;
    "kernel.nmi_watchdog"             = 0;
    "kernel.panic"                    = 30;
    "kernel.panic_on_oops"            = 1;
    "kernel.perf_event_paranoid"      = 0;
    "kernel.sched_rt_runtime_us"      = -1;
    "kernel.shmmax"                   = 17179869184;
    "kernel.threads-max"              = 4000000;

    # Network core
    "net.core.default_qdisc"          = "fq";
    "net.core.netdev_budget"          = 600;
    "net.core.netdev_budget_usecs"    = 8000;
    "net.core.netdev_max_backlog"     = 16384;
    "net.core.optmem_max"             = 131072;
    "net.core.rmem_default"           = 33554432;
    "net.core.rmem_max"               = 67108864;
    "net.core.rps_sock_flow_entries"  = 131072;
    "net.core.somaxconn"              = 65535;
    "net.core.wmem_default"           = 33554432;
    "net.core.wmem_max"               = 67108864;

    # IPv4 security
    "net.ipv4.conf.all.accept_source_route"     = 0;
    "net.ipv4.conf.all.rp_filter"               = 1;
    "net.ipv4.conf.default.accept_redirects"    = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.lo.accept_redirects"         = 0;
    "net.ipv4.conf.lo.accept_source_route"      = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts"      = 1;
    "net.ipv4.ip_forward"                       = 1;
    "net.ipv4.ip_local_port_range"              = "1024 65535";

    # ARP / neighbour cache
    "net.ipv4.neigh.default.gc_thresh1" = 8192;
    "net.ipv4.neigh.default.gc_thresh2" = 32768;
    "net.ipv4.neigh.default.gc_thresh3" = 65536;

    # TCP tuning
    "net.ipv4.tcp_abort_on_overflow"     = 1;
    "net.ipv4.tcp_adv_win_scale"         = -2;
    "net.ipv4.tcp_congestion_control"    = "bbr";
    "net.ipv4.tcp_ecn"                   = 1;
    "net.ipv4.tcp_fastopen"              = 3;
    "net.ipv4.tcp_fin_timeout"           = 30;
    "net.ipv4.tcp_keepalive_intvl"       = 5;
    "net.ipv4.tcp_keepalive_probes"      = 4;
    "net.ipv4.tcp_keepalive_time"        = 20;
    "net.ipv4.tcp_max_syn_backlog"       = 65535;
    "net.ipv4.tcp_max_tw_buckets"        = 2000000;
    "net.ipv4.tcp_moderate_rcvbuf"       = 1;
    "net.ipv4.tcp_mtu_probing"           = 1;
    "net.ipv4.tcp_no_metrics_save"       = 1;
    "net.ipv4.tcp_orphan_retries"        = 3;
    "net.ipv4.tcp_rfc1337"               = 1;
    "net.ipv4.tcp_rmem"                  = "4096 87380 67108864";
    "net.ipv4.tcp_sack"                  = 1;
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_syncookies"            = 1;
    "net.ipv4.tcp_timestamps"            = 1;
    "net.ipv4.tcp_tw_reuse"              = 1;
    "net.ipv4.tcp_window_scaling"        = 1;
    "net.ipv4.tcp_wmem"                  = "4096 87380 67108864";
    "net.ipv4.udp_rmem_min"             = 65536;
    "net.ipv4.udp_wmem_min"             = 65536;

    # Conntrack
    "net.netfilter.nf_conntrack_max" = 1048560;

    # VM
    "vm.dirty_background_bytes"  = 268435456;
    "vm.dirty_bytes"             = 1073741824;
    "vm.max_map_count"           = 262144;
    "vm.min_free_kbytes"         = 524288;
    "vm.nr_hugepages"            = 0;
    "vm.overcommit_memory"       = 2;
    "vm.overcommit_ratio"        = 99;
    "vm.panic_on_oom"            = 1;
    "vm.swappiness"              = 1;
    "vm.compaction_proactiveness" = 0;
    "vm.vfs_cache_pressure"      = 50;

    # IPv6 neighbour cache
    "net.ipv6.neigh.default.gc_thresh1" = 8192;
    "net.ipv6.neigh.default.gc_thresh2" = 32768;
    "net.ipv6.neigh.default.gc_thresh3" = 65536;

    # Async I/O
    "fs.aio-max-nr" = 1048576;
  };

  # ────────────────────────────────────────────────
  # Extra hosts
  # ────────────────────────────────────────────────
  networking.extraHosts = ''
    127.0.0.1 localhost
    ::1       localhost
    10.0.0.40 desk-threadripper desk-threadripper.local
    10.0.1.1  kpango-router
    10.0.1.2  kpango-switch
  '';
}
