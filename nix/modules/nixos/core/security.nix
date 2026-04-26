{ username, settings, ... }:

{
  # Security Hardening
  security.sudo = {
    wheelNeedsPassword = false;
    extraConfig = ''
      Defaults !always_set_home
      Defaults env_keep+="HOME"
    '';
  };
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "${toString settings.system.fileDescriptorLimit}"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "${toString settings.system.fileDescriptorLimit}"; }
    { domain = "*"; type = "soft"; item = "memlock"; value = "unlimited"; }
    { domain = "*"; type = "hard"; item = "memlock"; value = "unlimited"; }
  ];

  # User Configuration
  users.mutableUsers = false;
  users.users.${username} = {
    isNormalUser = true;
    uid = settings.system.uid;
    createHome = true;
    extraGroups = settings.userGroups;
  };
}