{
  pkgs,
  lib,
  hostname,
  settings,
  dotfilesPath,
  ...
}:

let
  # dockers/daemon.json is the single source of truth for Docker daemon
  # settings shared across genuine Arch Linux hosts (Makefile.d/install.mk's
  # dotfiles/install, which skips this file on NixOS) and NixOS hosts (read
  # here and in nix/modules/nixos/virtualization/docker.nix). See
  # docs/adr/ADR-0003-*.md. `dns` is overridden below rather than trusted from
  # the JSON's baked-in literals: settings.network.dockerDns resolves the same
  # IPs from the named constants in nix/core/settings.nix, so a future DNS
  # provider change stays in sync automatically. `runtimes.runsc/runu`
  # (gVisor, /usr/local/bin/*) is intentionally not in the shared JSON or
  # here: tr doesn't package gVisor, and NixOS wouldn't resolve those
  # /usr/local/bin paths anyway.
  baseDaemonSettings = builtins.fromJSON (builtins.readFile "${dotfilesPath}/dockers/daemon.json");
in
{
  # ────────────────────────────────────────────────
  # Docker daemon
  # ────────────────────────────────────────────────
  virtualisation.docker = {
    enable = settings.virtualisation.docker.enable;
    enableOnBoot = settings.virtualisation.docker.enableOnBoot;
    autoPrune.enable = settings.virtualisation.docker.autoPrune;

    daemon.settings = baseDaemonSettings // {
      dns = settings.network.dockerDns;
    };

    # Expose the local hostname registry (self-signed) without TLS
    extraOptions = "--insecure-registry ${hostname}.local:${toString settings.virtualisation.docker.insecureRegistryPort}";
  };

  # ────────────────────────────────────────────────
  # NVIDIA container runtime (GPU passthrough)
  # ────────────────────────────────────────────────
  hardware.nvidia-container-toolkit.enable = true;

  # ────────────────────────────────────────────────
  # Virtualisation extras
  # ────────────────────────────────────────────────
  virtualisation.libvirtd.enable = settings.virtualisation.libvirtd.enable;

  # NetworkManager must not manage docker bridge
  networking.networkmanager.unmanaged = lib.mkAfter [
    "interface-name:docker0"
    "interface-name:virbr0"
  ];

  # Packages useful for container work
  environment.systemPackages = with pkgs; [
    docker-compose
    docker-buildx
    kubectl
    kubectx
  ];
}
