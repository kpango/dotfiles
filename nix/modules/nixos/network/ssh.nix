{ settings, ... }:

{
  services.openssh = {
    enable = settings.network.ssh.enable;
    settings = {
      PasswordAuthentication = settings.network.ssh.passwordAuthentication;
      PermitRootLogin = settings.network.ssh.permitRootLogin;
    };
    extraConfig = settings.network.ssh.extraConfig;
  };
  services.tailscale.enable = settings.network.tailscale.enable;
}
