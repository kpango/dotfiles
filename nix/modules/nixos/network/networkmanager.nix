{ pkgs, hostname, settings, ... }:

{
  networking = {
    hostName = hostname;
    networkmanager = {
      enable = true;
      dns = settings.network.networkManager.dns;
      wifi = {
        backend = settings.network.networkManager.wifiBackend;
        scanRandMacAddress = false;
      };
      unmanaged = settings.network.networkManager.unmanaged;
      dispatcherScripts = [
        {
          source = pkgs.writeShellScript "nmcli-wifi-eth-autodetect" ''
            if [[ "''${1:0:2}" = "en" ]]; then
                case "$2" in
                    up)
                        ${pkgs.networkmanager}/bin/nmcli radio wifi off
                        ;;
                    down)
                        ${pkgs.networkmanager}/bin/nmcli radio wifi on
                        ;;
                esac
            fi
          '';
        }
        {
          source = pkgs.writeShellScript "nmcli-bond-auto-connect" ''
            INTERFACE=$1
            STATUS=$2

            if [ "$INTERFACE" == "${settings.network.networkManager.bondInterface}" ]; then
                case "$STATUS" in
                    up)
                        ${pkgs.networkmanager}/bin/nmcli dev set ${settings.network.networkManager.physicalInterface} autoconnect no
                        ${pkgs.networkmanager}/bin/nmcli dev disconnect ${settings.network.networkManager.physicalInterface}
                        ;;
                    down)
                        ${pkgs.networkmanager}/bin/nmcli dev set ${settings.network.networkManager.physicalInterface} autoconnect yes
                        ${pkgs.networkmanager}/bin/nmcli dev connect ${settings.network.networkManager.physicalInterface}
                        ;;
                esac
            fi
          '';
        }
      ];
    };
    nameservers = settings.network.nameservers;
    usePredictableInterfaceNames = false;
    extraHosts = ''
            ${settings.network.localHosts.ipv4} ${hostname} ${hostname}.local localhost
            ${settings.network.localHosts.ipv6} ${hostname} ${hostname}.local localhost
      ${settings.network.extraHosts}
    '';
    bridges.${settings.network.bridge.name}.interfaces = [ ];
    interfaces.${settings.network.bridge.name}.ipv4.addresses = [
      {
        address = settings.network.bridge.address;
        prefixLength = settings.network.bridge.prefixLength;
      }
    ];
  };

}
