{ ... }:

{
  imports = [
    ./firewall.nix
    ./networkmanager.nix
    ./dnsmasq.nix
    ./ssh.nix
  ];
}
