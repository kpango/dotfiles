{ lib, settings, ... }:

{
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    dnsovertls = "opportunistic";
    domains = [ "~." ];
    fallbackDns = settings.network.resolved.fallbackDns;
    extraConfig = ''
      DNS=${lib.concatStringsSep " " settings.network.resolved.dns}
      Cache=yes
    '';
  };
}
