{
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
      storageDriver = "overlay2";
    };
    lxd = {
      enable = true;
    };
    # virtualbox.host = {
    #   enable = true;
    #   headless = true;
    #   enableExtensionPack = true;
    # };
  };
}
