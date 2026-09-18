{
  hostname,
  settings,
  dotfilesPath,
  ...
}:

let
  # dockers/daemon.json is the single source of truth for Docker daemon
  # settings shared across genuine Arch Linux hosts (deployed via
  # Makefile.d/install.mk's dotfiles/install, which skips this file entirely
  # on NixOS) and NixOS hosts (read here). See docs/adr/ADR-0003-*.md.
  # `dns` is overridden below rather than trusted from the JSON's baked-in
  # literals: settings.network.dockerDns resolves the same IPs from the named
  # constants in nix/core/settings.nix, so a future DNS provider change stays
  # in sync automatically for every Nix-side consumer without needing a
  # parallel edit to dockers/daemon.json.
  # `runtimes.runsc/runu` (gVisor, /usr/local/bin/*) is intentionally NOT in
  # the shared JSON: NixOS doesn't use /usr/local/bin-style paths, and no
  # NixOS host here currently packages gVisor — Makefile.d/install.mk adds it
  # back for genuine Arch hosts only, via a jq merge at deploy time.
  baseDaemonSettings = builtins.fromJSON (builtins.readFile "${dotfilesPath}/dockers/daemon.json");
in
{
  virtualisation = {
    docker = {
      enable = settings.virtualisation.docker.enable;
      enableOnBoot = settings.virtualisation.docker.enableOnBoot;
      autoPrune.enable = settings.virtualisation.docker.autoPrune;
      daemon.settings = baseDaemonSettings // {
        dns = settings.network.dockerDns;
      };
      extraOptions = "--insecure-registry ${hostname}.local:${toString settings.virtualisation.docker.insecureRegistryPort}";
    };
    libvirtd.enable = settings.virtualisation.libvirtd.enable;
  };
}
