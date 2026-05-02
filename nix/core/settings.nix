let
  # Common Network Constants
  cloudflareDnsV4Primary = "1.1.1.1";
  cloudflareDnsV4Secondary = "1.0.0.1";
  cloudflareDnsV6Primary = "2606:4700:4700::1111";
  cloudflareDnsV6Secondary = "2606:4700:4700::1001";
  googleDnsV4Primary = "8.8.8.8";
  googleDnsV4Secondary = "8.8.4.4";
  googleDnsV6Primary = "2001:4860:4860::8888";
  googleDnsV6Secondary = "2001:4860:4860::8844";
  quad9DnsV4Primary = "9.9.9.9";
  quad9DnsV4Secondary = "149.112.112.112";

  # Common Sysctl Values
  sysctlMaxFiles = 19349474;
  sysctlNetMaxBuffer = 33554432;
  sysctlTcpBufferLimits = "4096 87380 16777216";
  sysctlUdpMinBuffer = 8192;
  sysctlSomaxconn = 65535;

  # Common Ports
  portSSH = 22;
  portHTTP = 80;
  portHTTPS = 443;
  portDev3000 = 3000;
  portDev8000 = 8000;
  portDev8080 = 8080;
  portDev8443 = 8443;
  portDev9999 = 9999;

  portSteamRemotePlayTCP1 = 27036;
  portSteamRemotePlayTCP2 = 27037;
  portSteamRemotePlayUDP1 = 27031;
  portSteamRemotePlayUDP2 = 27037;

  portMoshStart = 60000;
  portMoshEnd = 61000;

in
{
  # User settings
  username = "kpango";
  fullName = "kpango";
  email = "kpango@local.dev";

  # Home directories base paths (parent of ~, not the dotfiles repo)
  homeDirectories = {
    linux = "/home";
    darwin = "/Users";
  };

  # Absolute path to the root of this dotfiles repository
  dotfilesDir = {
    linux = "/home/kpango/go/src/github.com/kpango/dotfiles";
    darwin = "/home/kpango/go/src/github.com/kpango/dotfiles";
  };

  # Localization settings
  timeZone = "Asia/Tokyo";
  locale = "en_US.UTF-8";

  # UI / Font settings
  fonts = {
    monospace = "HackGen Console NF";
    emoji = "Noto Color Emoji";
  };

  # Network & Infrastructure settings
  network = {
    # System nameservers
    nameservers = [
      cloudflareDnsV4Primary
      cloudflareDnsV4Secondary
      googleDnsV4Primary
      googleDnsV4Secondary
    ];
    # Dnsmasq caching servers
    dnsmasqCacheSize = 10000;
    dnsmasqServers = [
      cloudflareDnsV6Primary
      googleDnsV6Primary
      cloudflareDnsV6Secondary
      googleDnsV6Secondary
      "2606:4700:4700::1112"
      "2606:4700:4700::1002"
      "2620:fe::11"
      "2620:fe::fe"
      "2620:fe::fe:11"
      "2620:fe::9"
      "2620:fe::10"
      "2620:fe::fe:10"
      "1.1.1.2"
      cloudflareDnsV4Primary
      googleDnsV4Primary
      "9.9.9.11"
      quad9DnsV4Primary
      "1.0.0.2"
      cloudflareDnsV4Secondary
      googleDnsV4Secondary
      "9.9.9.10"
      "149.112.112.11"
      quad9DnsV4Secondary
      "149.112.112.10"
    ];
    # NTP Servers
    ntpServers = [
      "0.jp.pool.ntp.org"
      "1.jp.pool.ntp.org"
      "2.jp.pool.ntp.org"
      "3.jp.pool.ntp.org"
      "ntp.dnsbalance.ring.gr.jp"
      "ntp.jst.mfeed.ad.jp"
      "ntp.nict.jp"
      "ntp.ring.gr.jp"
      "ntp1.jst.mfeed.ad.jp"
      "ntp1.v6.mfeed.ad.jp"
      "ntp2.jst.mfeed.ad.jp"
      "ntp2.v6.mfeed.ad.jp"
      "ntp3.jst.mfeed.ad.jp"
      "ntp3.v6.mfeed.ad.jp"
      "s2csntp.miz.nao.ac.jp"
      "time.google.com"
    ];
    # Custom Extra Hosts Mapping
    extraHosts = ''
      127.0.0.2 other-localhost
      10.0.1.1 kpango-router
      10.0.1.2 kpango-switch
      192.168.1.1 kato-router
      192.168.1.2 kato-switch
    '';
    # Firewall Configuration
    firewall = {
      allowedTCPPorts = [
        portSSH
        portHTTP
        portHTTPS
        portDev3000
        portDev8000
        portDev8080
        portDev8443
        portDev9999
        portSteamRemotePlayTCP1
        portSteamRemotePlayTCP2
      ];
      allowedUDPPorts = [ portSteamRemotePlayUDP1 portSteamRemotePlayUDP2 ];
      allowedUDPPortRanges = [{ from = portMoshStart; to = portMoshEnd; }];
      externalInterface = "wlp4s0";
      extraCommands = "iptables -I INPUT -p udp -m udp --dport 32768:60999 -j ACCEPT";
    };
    # Bridge network configuration
    bridge = {
      name = "cbr0";
      address = "10.10.0.1";
      prefixLength = 24;
    };
    # NetworkManager specifics
    networkManager = {
      dns = "dnsmasq";
      wifiBackend = "iwd";
      unmanaged = [ "docker0" ];
      bondInterface = "bond0";
      physicalInterface = "A";
      connectionMode = "0600";
    };
    # Local loopback addresses
    localHosts = {
      ipv4 = "127.0.0.1";
      ipv6 = "::1";
    };
    # Persistent network interfaces (udev rules)
    interfaces = {
      eth0 = "f0:2f:74:d4:37:35";
      sfp0 = "64:9d:99:b1:03:44";
      sfp1 = "64:9d:99:b1:03:45";
    };
    # SSH & VPN settings
    ssh = {
      enable = true;
      passwordAuthentication = false;
      permitRootLogin = "no";
      extraConfig = "StreamLocalBindUnlink yes";
    };
    tailscale = {
      enable = true;
    };
  };

  # Services Configuration
  services = {
    gopls = {
      port = 37374;
      logfile = "/tmp/gopls.daemon.log";
    };
  };

  # Virtualization Configuration
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune = true;
      insecureRegistryPort = portHTTP;
    };
    lxd = {
      enable = true;
    };
    libvirtd = {
      enable = true;
    };
    k3s = {
      enable = true;
      role = "server";
      extraFlags = [
        "--cluster-init"
        "--disable=traefik,servicelb"
      ];
    };
  };

  # macOS Specific Configuration
  darwin = {
    homebrew = {
      enable = true;
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
      taps = [
        "homebrew/autoupdate"
        "homebrew/bundle"
        "homebrew/cask-fonts"
      ];
      casks = [
        "discord"
        "font-hackgen-nerd"
        "ghostty"
        "google-chrome"
        "google-japanese-ime"
        "messenger"
        "slack"
        "tailscale"
        "visual-studio-code"
        "zoom"
      ];
    };
    masApps = {
      "Tailscale" = 1475387142;
    };
    dock = {
      wvous-br-corner = 14; # 14 = Put Display to Sleep
      autohide = true;
      largesize = 68;
      mineffect = "genie";
      showRecents = false;
    };
    preferences = {
      AppleInterfaceStyle = "Dark";
      AppleLanguages = [ "en-JP" "ja-JP" ];
      screencaptureType = "png";
    };
  };

  # Hardware/Platform architecture settings
  system = {
    linux = "x86_64-linux";
    darwin = "aarch64-darwin";
    uid = 1000;
    fileDescriptorLimit = 524288;
    # Filesystem Labels & Options
    disks = {
      rootLabel = "root";
      rootOptions = [ "rw" "relatime" "attr2" "inode64" "logbufs=8" "logbsize=32k" "noquota" "noatime" "nodiratime" "discard" ];
      bootLabel = "boot";
      bootOptions = [ "rw" "relatime" "fmask=0022" "dmask=0022" "codepage=437" "iocharset=iso8859-1" "shortname=mixed" "utf8" "errors=remount-ro" ];
    };
    # Kernel & OS Performance Tuning
    kernel = {
      # Universal params applied to all generic NixOS hosts via modules/nixos/core/boot.nix.
      # zswap.zpool is intentionally absent here: desktops use zsmalloc, laptops use z3fold —
      # set in each host/profile's kernelParams.
      params = [
        "quiet"
        "nowatchdog"
        "cgroup_no_v1=all"
        "zswap.enabled=1"
        "zswap.compressor=zstd"
      ];
      blacklistedModules = [
        "pcspkr"
        "intel_pmc_bxt"
        "iTCO_vendor_support"
        "iTCO_wdt"
        "snd_pcsp"
      ];
      sysctl = {
        "fs.aio-max-nr" = sysctlMaxFiles;
        "fs.file-max" = sysctlMaxFiles;
        "fs.epoll.max_user_watches" = 39688724;
        "kernel.nmi_watchdog" = 0;
        "kernel.panic" = 30;
        "kernel.perf_event_paranoid" = 0;
        "kernel.sched_rt_runtime_us" = -1;
        "kernel.shmmax" = 17179869184;
        "kernel.threads-max" = 4000000;
        "net.core.default_qdisc" = "fq";
        "net.core.netdev_budget" = 600;
        "net.core.netdev_budget_usecs" = 8000;
        "net.core.netdev_max_backlog" = 16384;
        "net.core.optmem_max" = 40960;
        "net.core.rmem_default" = sysctlNetMaxBuffer;
        "net.core.rmem_max" = sysctlNetMaxBuffer;
        "net.core.rps_sock_flow_entries" = 32768;
        "net.core.somaxconn" = sysctlSomaxconn;
        "net.core.wmem_default" = sysctlNetMaxBuffer;
        "net.core.wmem_max" = sysctlNetMaxBuffer;
        "net.ipv4.conf.all.accept_source_route" = 0;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_source_route" = 0;
        "net.ipv4.conf.lo.accept_redirects" = 0;
        "net.ipv4.conf.lo.accept_source_route" = 0;
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
        "net.ipv4.ip_forward" = 1;
        "net.ipv4.ip_local_port_range" = "1024 65535";
        "net.ipv4.tcp_abort_on_overflow" = 1;
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.ipv4.tcp_ecn" = 1;
        "net.ipv4.tcp_fack" = 1;
        "net.ipv4.tcp_fastopen" = 3;
        "net.ipv4.tcp_fin_timeout" = 30;
        "net.ipv4.tcp_keepalive_intvl" = 5;
        "net.ipv4.tcp_keepalive_probes" = 4;
        "net.ipv4.tcp_keepalive_time" = 20;
        "net.ipv4.tcp_low_latency" = 0;
        "net.ipv4.tcp_max_syn_backlog" = sysctlSomaxconn;
        "net.ipv4.tcp_max_tw_buckets" = 2000000;
        "net.ipv4.tcp_moderate_rcvbuf" = 1;
        "net.ipv4.tcp_no_metrics_save" = 1;
        "net.ipv4.tcp_orphan_retries" = 3;
        "net.ipv4.tcp_rfc1337" = 1;
        "net.ipv4.tcp_rmem" = sysctlTcpBufferLimits;
        "net.ipv4.tcp_sack" = 1;
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.tcp_timestamps" = 0;
        "net.ipv4.tcp_tw_reuse" = 1;
        "net.ipv4.tcp_window_scaling" = 1;
        "net.ipv4.tcp_wmem" = sysctlTcpBufferLimits;
        "net.ipv4.udp_rmem_min" = sysctlUdpMinBuffer;
        "net.ipv4.udp_wmem_min" = sysctlUdpMinBuffer;
        "net.nf_conntrack_max" = 1048560;
        "vm.max_map_count" = 262144;
        "vm.nr_hugepages" = 4096;
        "vm.overcommit_memory" = 2;
        "vm.overcommit_ratio" = 99;
        "vm.panic_on_oom" = 1;
        "vm.swappiness" = 1;
        "vm.vfs_cache_pressure" = 50;
      };
      extraModprobeConfig = ''
        # nvidia-tweaks.conf
        options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_EnableStreamMemOPs=1
        options nvidia_drm modeset=1
      '';
    };
  };

  # Hardware Power & Cooling settings
  hardware = {
    maintenance = {
      fstrim = true;
      locate = true;
    };
    gpuStatePath = "/tmp/gpu_state";
    battery = {
      startCharge = 60;
      stopCharge = 90;
    };
    tlp = {
      runtimePmDriverBlacklist = "amdgpu nouveau nvidia radeon";
      restoreThresholdsOnBat = 1;
      wolDisable = "N";
    };
    thinkfan = {
      sensors = [
        { type = "tpacpi"; query = "/proc/acpi/ibm/fan"; }
        { type = "hwmon"; query = "/sys/devices/virtual/thermal/thermal_zone0/temp"; }
        { type = "hwmon"; query = "/sys/devices/platform/coretemp.0/hwmon/hwmon1/temp1_input"; }
      ];
      levels = [
        [ 0 0 47 ]
        [ 1 45 49 ]
        [ 2 47 52 ]
        [ 3 50 57 ]
        [ 4 55 62 ]
        [ 5 60 77 ]
        [ 7 73 93 ]
        [ 127 85 32767 ]
      ];
    };
  };

  # User groups configuration
  userGroups = [
    "audio"
    "autologin"
    "disk"
    "docker"
    "input"
    "libvirtd"
    "lxd"
    "mysql"
    "networkmanager"
    "power"
    "pulse"
    "pulse-access"
    "sshd"
    "storage"
    "systemd-journal"
    "uinput"
    "vboxusers"
    "video"
    "wheel"
    "wireshark"
  ];

  # Nix and Nixpkgs Settings
  nix = {
    allowUnfree = true;
    allowBroken = false;
    allowUnfreeRedistributable = true;
    pulseaudio = true;
    hardwareClockInLocalTime = true;
    chromium = {
      enablePepperFlash = false;
      enablePepperPdf = true;
      enableWideVine = true;
    };
  };

  # Desktop Environment Settings
  desktop = {
    editor = "hx";
    keyboard = {
      layout = "us";
      options = "ctrl:nocaps";
    };
    imModule = "fcitx5";
    aliases = {
      colima = "colima start --cpu 6 --memory 12 --disk 100 --arch aarch64 --vm-type vz --vz-rosetta";
      nixUpdate = "darwin-rebuild switch --flake ~/.config/nix-darwin#macbook";
    };
    audio = {
      enable = true;
      support32Bit = true;
    };
    printing = {
      enable = true;
    };
  };
}
