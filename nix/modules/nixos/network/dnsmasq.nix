{ lib, settings, ... }:

let
  dnsmasqServersConfig = lib.concatMapStringsSep "\n" (s: "      server=${s}") settings.network.dnsmasqServers;
in
{
  environment.etc = {
    "NetworkManager/dnsmasq.d/dnsmasq.conf".text = ''
      cache-size=${toString settings.network.dnsmasqCacheSize}
      listen-address=${settings.network.localHosts.ipv4},${settings.network.localHosts.ipv6}
${dnsmasqServersConfig}
    '';
  };
}