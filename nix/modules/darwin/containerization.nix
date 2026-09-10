{ inputs, ... }:

{
  # apple/container (aarch64-darwin only), replacing colima/docker as the container backend
  # (see packages/darwin.nix — colima/docker removed from home.packages). Packaged via
  # inputs.nix-apple-container (flake.nix) rather than a curl+pkg-installer bootstrap: the
  # CLI binary and its Kata Linux kernel are both Nix derivations, so the version is pinned
  # by flake.lock like everything else here instead of a hand-maintained release URL (the
  # old Makefile.d/nix.mk bootstrap this replaces was still pinned to the pre-1.0 0.4.1
  # release and had no way to notice it was stale).
  imports = [ inputs.nix-apple-container.darwinModules.default ];

  # `user` defaults to config.system.primaryUser, already set in system.nix — no need to
  # repeat it here.
  services.containerization.enable = true;

  # Container-to-container DNS (`<name>.test`) is intentionally NOT wired in here. It isn't
  # a declarative option of this module — it's a one-time `container system dns create test`
  # (needs an interactive sudo password) plus a ~/.config/container/config.toml edit on the
  # base apple/container CLI. Both are inappropriate to run unconditionally on every
  # `darwin-rebuild switch` (interactive password prompt during activation, and it disables
  # iCloud Private Relay — an opt-in tradeoff, not a default). See README.md for the
  # one-time manual setup command.
}
