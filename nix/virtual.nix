{ config, ... }:

{
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      liveRestore = true;
      autoPrune = {
        enable = true;
      };
      storageDriver = "overlay2";
      extraOptions = "--insecure-registry ${config.networking.hostName}.local:80";
    };
    lxd = {
      enable = true;
    };
    libvirtd = {
      enable = true;
    };
    # virtualbox.host = {
    #   enable = true;
    #   headless = true;
    #   enableExtensionPack = true;
    # };
  };
}
