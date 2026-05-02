{ hostname, settings, ... }:

{
  virtualisation = {
    docker = {
      enable = settings.virtualisation.docker.enable;
      enableOnBoot = settings.virtualisation.docker.enableOnBoot;
      autoPrune.enable = settings.virtualisation.docker.autoPrune;
      daemon.settings = builtins.fromJSON (builtins.readFile ../../../../dockers/daemon.json);
      extraOptions = "--insecure-registry ${hostname}.local:${toString settings.virtualisation.docker.insecureRegistryPort}";
    };
    lxd.enable = settings.virtualisation.lxd.enable;
    libvirtd.enable = settings.virtualisation.libvirtd.enable;
  };
}
