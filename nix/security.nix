{ config, lib, ... }:
{
  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
      extraConfig = ''
        Defaults !always_set_home
        Defaults env_keep+="HOME"
      '';
    };
  };
}
