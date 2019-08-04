{ config, ... }:

{
  networking = {
    bridges = {
      cbr0 = {
        interfaces = [];
      };
    };
    interfaces = {
      cbr0 = {
        ipv4.addresses = [
          {
            address = "10.10.0.1";
            prefixLength = 24;
          }
        ];
      };
    };

    # TODO head -c 8 /etc/machine-id
    # hostId = "kubernetespangolang";
    hostName = "kpango.nix.dev";
    usePredictableInterfaceNames = false;
    networkmanager = {
      enable = true;
      dns = "dnsmasq";
    };
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
      "8.8.4.4"
    ];
    firewall = {
      enable = true;
      allowPing = false;
      allowedTCPPorts = [
        22
        80
        443
        3000
        8080
        8000
        8443
        9999
        27036
        27037
      ];
      allowedUDPPorts = [
        27031
        27037
      ];
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
      checkReversePath = false;
      extraCommands = ''
        iptables -I INPUT -p udp -m udp --dport 32768:60999 -j ACCEPT
      '';
    };
    nat = {
      enable = true;
      internalInterfaces = ["ve-+"];
      externalInterface = "wlp4s0";
    };
    # extraHosts = ''
      # 127.0.0.1 kpango.nix.dev.local localhost
    extraHosts = ''
      127.0.0.1 ${config.networking.hostName} ${config.networking.hostName}.local localhost
      127.0.0.2 other-localhost
      10.0.1.1 kpango-router
      10.0.1.2 kpango-switch
      192.168.1.1 kato-router
      192.168.1.2 kato-switch
      ::1 ${config.networking.hostName} ${config.networking.hostName}.local localhost
    '';
  };
}
