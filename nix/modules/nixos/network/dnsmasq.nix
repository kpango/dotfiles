{ lib, settings, ... }:

{
  environment.etc."NetworkManager/dnsmasq.d/dnsmasq.conf".text =
    lib.concatStringsSep "\n"
      ([
        "cache-size=${toString settings.network.dnsmasqCacheSize}"
        "listen-address=${settings.network.localHosts.ipv4},${settings.network.localHosts.ipv6}"
      ] ++ map (s: "server=${s}") settings.network.dnsmasqServers)
    + "\n";
}
