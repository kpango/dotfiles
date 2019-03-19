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
    pam = {
      loginLimits = [
        {
          domain = "*";
          type = "soft";
          item = "nofile";
          value = "65535";
        }
        {
          domain = "*";
          type = "hard";
          item = "nofile";
          value = "65535";
        }
      ];
    };
  };
}
