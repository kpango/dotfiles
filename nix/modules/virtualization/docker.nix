{ pkgs, lib, ... }:

{
  # ────────────────────────────────────────────────
  # Docker daemon
  # Settings translated from /etc/docker/daemon.json
  # ────────────────────────────────────────────────
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;

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

      # DNS (matches /etc/docker/daemon.json)
      dns = [
        "1.1.1.2"
        "1.1.1.1"
        "8.8.8.8"
        "9.9.9.11"
        "9.9.9.9"
        "1.0.0.2"
        "1.0.0.1"
        "8.8.4.4"
        "9.9.9.10"
        "149.112.112.11"
        "149.112.112.112"
        "149.112.112.10"
        "2606:4700:4700::1112"
        "2606:4700:4700::1002"
        "2606:4700:4700::1111"
        "2606:4700:4700::1001"
        "2001:4860:4860::8888"
        "2001:4860:4860::8844"
        "2620:fe::11"
        "2620:fe::fe"
        "2620:fe::fe:11"
        "2620:fe::9"
        "2620:fe::10"
        "2620:fe::fe:10"
      ];
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
    extraOptions = "--insecure-registry desk-threadripper.local:80";
  };

  # ────────────────────────────────────────────────
  # NVIDIA container runtime (GPU passthrough)
  # ────────────────────────────────────────────────
  hardware.nvidia-container-toolkit.enable = true;

  # ────────────────────────────────────────────────
  # Virtualisation extras
  # ────────────────────────────────────────────────
  virtualisation.libvirtd.enable = true;

  # NetworkManager must not manage docker bridge
  networking.networkmanager.unmanaged = lib.mkAfter [ "docker0" "virbr0" ];

  # Packages useful for container work
  environment.systemPackages = with pkgs; [
    docker-compose
    docker-buildx
    kubectl
    kubectx
  ];
}
