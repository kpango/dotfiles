{ pkgs, username, settings, ... }:

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
    uid          = settings.system.uid;
    home         = "/home/${username}";
    createHome   = true;
    shell        = pkgs.zsh;
    extraGroups  = settings.userGroups;
    # Set your SSH public key(s) here or via a keyFile:
    #   openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... ${username}@..." ];
    openssh.authorizedKeys.keys = [];
  };
}