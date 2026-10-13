{ lib, settings, ... }:

{
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    # NextDNS supports DoT with SNI auth (DNS= entries carry IP#hostname). Strict mode:
    # if the TLS handshake with NextDNS fails, resolved refuses to downgrade to plain DNS —
    # this prevents profile 21553f (ad-block / parental control / logs) from being bypassed
    # when the network path to NextDNS is degraded.
    dnsovertls = "true";
    domains = [ "~." ];
    fallbackDns = settings.network.resolved.fallbackDns;
    settings.Resolve = {
      DNS = lib.concatStringsSep " " settings.network.resolved.dns;
      # Explicit empty FallbackDNS overrides resolved's compiled-in defaults
      # (which include Cloudflare/Google) and enforces fail-closed when NextDNS is down.
      FallbackDNS = "";
      Cache = "yes";
    };
  };
}
