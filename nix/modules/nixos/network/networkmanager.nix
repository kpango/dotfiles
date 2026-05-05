{ pkgs, lib, hostname, settings, ... }:

{
  networking = {
    hostName = hostname;
    networkmanager = {
      enable = true;
      # lib.mkForce: Tailscale's NixOS module enables services.resolved which sets
      # networking.networkmanager.dns = "systemd-resolved" at the same priority.
      dns = lib.mkForce settings.network.networkManager.dns;
      wifi = {
        backend = settings.network.networkManager.wifiBackend;
        scanRandMacAddress = false;
      };
      unmanaged = settings.network.networkManager.unmanaged;
      dispatcherScripts = [
        {
          # Disable wifi when a wired ethernet interface (eth* or en*) comes up,
          # re-enable when it goes down. Handles both legacy names (eth0, with
          # usePredictableInterfaceNames = false) and predictable names (eno1, enp3s0).
          source = pkgs.writeShellScript "nmcli-wifi-eth-autodetect" ''
            iface="$1"
            if [[ "$iface" =~ ^eth || "$iface" =~ ^en ]]; then
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
      ];
    };
    nameservers = settings.network.nameservers;
    usePredictableInterfaceNames = false;
    extraHosts = lib.concatStringsSep "\n" [
      "${settings.network.localHosts.ipv4} ${hostname} ${hostname}.local localhost"
      "${settings.network.localHosts.ipv6} ${hostname} ${hostname}.local localhost"
      settings.network.extraHosts
    ];
    bridges.${settings.network.bridge.name}.interfaces = [ ];
    interfaces.${settings.network.bridge.name}.ipv4.addresses = [
      {
        address = settings.network.bridge.address;
        prefixLength = settings.network.bridge.prefixLength;
      }
    ];
  };

}
