{ lib, settings, ... }:

{
  environment.etc."NetworkManager/dnsmasq.d/dnsmasq.conf".text =
    lib.concatStringsSep "\n" (
      [
        "cache-size=${toString settings.network.dnsmasqCacheSize}"
        "listen-address=${settings.network.localHosts.ipv4},${settings.network.localHosts.ipv6}"
        "no-resolv"
        "domain-needed"
        "bogus-priv"
        "strict-order"
      ]
      ++ map (s: "server=${s}") settings.network.dnsmasqServers
      ++ [
        # NextDNS requires the profile ID appended to each query (CPE ID extension) so the
        # anycast endpoints in settings.network.dnsmasqServers can identify this device.
        "add-cpe-id=${settings.network.nextdns.profileId}"
      ]
    )
    + "\n";
}
