{
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
    };
    lxd = {
      enable = true;
    };
    virtualbox.host = {
      enable = true;
      headless = true;
      enableExtensionPack = true;
    };
  };
}
