{ hostname, settings, ... }:

{
  virtualisation = {
    docker = {
      enable = settings.virtualisation.docker.enable;
      enableOnBoot = settings.virtualisation.docker.enableOnBoot;
      autoPrune.enable = settings.virtualisation.docker.autoPrune;
      daemon.settings = {
        debug = false;
        init = true;
        "log-driver" = "local";
        "log-opts" = {
          "max-size" = "10m";
          "max-file" = "3";
          "compress" = "true";
        };
        dns = settings.network.dnsmasqServers;
        "dns-opts" = [ "timeout:5" ];
        "storage-driver" = "overlay2";
        "live-restore" = true;
        experimental = true;
        features = { buildkit = true; };
        "default-shm-size" = "2g";
        "max-concurrent-downloads" = 24;
        "max-concurrent-uploads" = 24;
        "max-download-attempts" = 24;
        "shutdown-timeout" = 10;
        "selinux-enabled" = false;
        builder = {
          gc = {
            enabled = true;
            defaultKeepStorage = "50GB";
          };
          driver = "docker-container";
        };
        "default-ulimits" = {
          nofile = { Name = "nofile"; Hard = 1048576; Soft = 1048576; };
          memlock = { Name = "memlock"; Hard = -1; Soft = -1; };
        };
        "registry-mirrors" = [ "https://mirror.gcr.io" ];
      };
      extraOptions = "--insecure-registry ${hostname}.local:${toString settings.virtualisation.docker.insecureRegistryPort}";
    };
    libvirtd.enable = settings.virtualisation.libvirtd.enable;
  };
}
