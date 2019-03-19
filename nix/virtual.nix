{
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
      storageDriver = "overlay2";
      # TODO configがないらしい
      extraOptions = "--insecure-registry kpango.nix.dev.local:80";
      # extraOptions = "--insecure-registry ${config.networking.hostName}.local:80";
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
