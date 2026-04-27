{ settings, ... }:

{
  services.chrony = {
    enable = true;
    servers = settings.network.ntpServers;
    extraConfig = ''
      minsources 2
      makestep 1.0 3
      leapsecmode slew
      stratumweight 0
      local stratum 10
      noclientlog
      logchange 0.5
      deny all
      port 0
      bindaddress ${settings.network.localHosts.ipv4}
      bindaddress ${settings.network.localHosts.ipv6}
      rtconutc
      rtcsync
    '';
  };
}