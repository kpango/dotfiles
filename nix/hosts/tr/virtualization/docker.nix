{ pkgs, lib, hostname, settings, ... }:

{
  # ────────────────────────────────────────────────
  # Docker daemon
  # Settings translated from /etc/docker/daemon.json
  # ────────────────────────────────────────────────
  virtualisation.docker = {
    enable = settings.virtualisation.docker.enable;
    enableOnBoot = settings.virtualisation.docker.enableOnBoot;
    autoPrune.enable = settings.virtualisation.docker.autoPrune;

    daemon.settings = {
      # Logging
      debug = false;
      init = true;
      "log-driver" = "local";
      "log-opts" = {
        "max-size" = "10m";
        "max-file" = "3";
        "compress" = "true";
      };

      # Networking
      mtu = 9000;
      ipv6 = true;
      bip = "192.168.249.1/24";
      "fixed-cidr" = "192.168.249.0/25";
      "fixed-cidr-v6" = "2001:db8:1::/64";
      "default-gateway" = "192.168.249.254";
      "default-address-pools" = [
        { base = "10.201.0.0/16"; size = 24; }
        { base = "10.202.0.0/16"; size = 24; }
        { base = "10.203.0.0/16"; size = 24; }
        { base = "10.27.16.0/22"; size = 24; }
      ];

      dns = settings.network.dnsmasqServers;
      "dns-opts" = [ "timeout:5" ];

      # Storage
      "storage-driver" = "overlay2";
      "live-restore" = true;
      experimental = true;
      features = { buildkit = true; };
      "default-shm-size" = "2g";

      # Concurrency
      "max-concurrent-downloads" = 24;
      "max-concurrent-uploads" = 24;
      "max-download-attempts" = 24;

      # GC / builder
      builder = {
        gc = {
          enabled = true;
          defaultKeepStorage = "50GB";
        };
        driver = "docker-container";
      };

      # Ulimits
      "default-ulimits" = {
        nofile = { Name = "nofile"; Hard = 1048576; Soft = 1048576; };
        memlock = { Name = "memlock"; Hard = -1; Soft = -1; };
      };

      # Security / isolation
      "selinux-enabled" = false;
      "shutdown-timeout" = 10;

      # Registry mirrors
      "registry-mirrors" = [ "https://mirror.gcr.io" ];
    };

    # Expose the local hostname registry (self-signed) without TLS
    extraOptions = "--insecure-registry ${hostname}.local:${toString settings.virtualisation.docker.insecureRegistryPort}";
  };

  # ────────────────────────────────────────────────
  # NVIDIA container runtime (GPU passthrough)
  # ────────────────────────────────────────────────
  hardware.nvidia-container-toolkit.enable = true;

  # ────────────────────────────────────────────────
  # Virtualisation extras
  # ────────────────────────────────────────────────
  virtualisation.libvirtd.enable = settings.virtualisation.libvirtd.enable;

  # NetworkManager must not manage docker bridge
  networking.networkmanager.unmanaged = lib.mkAfter [ "interface-name:docker0" "interface-name:virbr0" ];

  # Packages useful for container work
  environment.systemPackages = with pkgs; [
    docker-compose
    docker-buildx
    kubectl
    kubectx
  ];
}
