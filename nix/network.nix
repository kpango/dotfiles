{
  networking = {
    hostName = "kpango";
    networkmanager = {
      enable = true;
      dns = "dnsmasq";
    };
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 3000 8080 8000 8443 9999 ];
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
      extraCommands = ''
        iptables -I INPUT -p udp -m udp --dport 32768:60999 -j ACCEPT
      '';
    };
    nat = {
      enable = true;
      internalInterfaces = ["ve-+"];
      externalInterface = "wlp4s0";
    };
  };
}
