{ settings, ... }:

{
  networking.firewall = {
    enable = true;
    allowPing = false;
    allowedTCPPorts = settings.network.firewall.allowedTCPPorts;
    allowedUDPPorts = settings.network.firewall.allowedUDPPorts;
    allowedUDPPortRanges = settings.network.firewall.allowedUDPPortRanges;
    checkReversePath = false;
    extraCommands = settings.network.firewall.extraCommands;
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];
    externalInterface = settings.network.firewall.externalInterface;
  };
}
