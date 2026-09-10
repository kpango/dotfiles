---
name: nix-patterns
description: Nix flakes, derivations, overlays, home-manager, devShells, and nixpkgs patterns for reproducible system configuration and development environments. 実装作業自体は nix-expert agent に委譲する(infra-config-adversarial-reviewerはGATE直前の構文/スキーマレビュー専用で別物)。
trigger: /nix-patterns
---

# Nix Patterns

## Core Principles

- Flakes are the standard — avoid legacy `nix-env` / `default.nix` entry points
- Inputs are pinned; update with `nix flake update`
- `nixpkgs.follows` prevents input duplication across flake inputs
- Home-manager manages per-user state; NixOS/nix-darwin manage system state

## Flake Structure

```nix
{
  description = "kpango dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";  # avoids duplicate nixpkgs
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    homeConfigurations."kpango" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [ ./home.nix ];
    };

    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      packages = with nixpkgs.legacyPackages.x86_64-linux; [ go rustup buf ];
    };
  };
}
```

## Derivations

```nix
# stdenv.mkDerivation for C/Go/Rust packages
{ lib, stdenv, fetchFromGitHub, go }:
stdenv.mkDerivation rec {
  pname = "myapp";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "kpango";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-AAAA...";  # leave empty to get hash error with correct value
  };

  nativeBuildInputs = [ go ];  # build-time only
  buildInputs = [];             # runtime deps

  buildPhase = "go build -o $out/bin/${pname} ./...";
  installPhase = "true";

  meta.license = lib.licenses.asl20;
}

# buildGoModule for Go projects
{ buildGoModule, fetchFromGitHub }:
buildGoModule {
  pname = "myapp";
  version = "1.0.0";
  src = fetchFromGitHub { ... };
  vendorHash = "sha256-...";  # null if not vendored
}
```

## Overlays

```nix
# Overlay: add or override packages
overlays.default = final: prev: {
  myapp = final.callPackage ./pkgs/myapp.nix {};

  # Override existing package
  go = prev.go.overrideAttrs (old: {
    version = "1.23.0";
    src = prev.fetchurl { url = "..."; hash = "..."; };
  });
};

# Apply overlay in flake outputs
pkgs = import nixpkgs {
  inherit system;
  overlays = [ self.overlays.default ];
};
```

## Home Manager

```nix
# home.nix
{ pkgs, config, ... }: {
  home.username = "kpango";
  home.homeDirectory = "/home/kpango";
  home.stateVersion = "24.11";  # don't change after initial setup

  home.packages = with pkgs; [ ripgrep fd fzf jq ];

  # Managed config file (immutable — symlinked from /nix/store)
  xdg.configFile."helix/config.toml".source = ./helix/config.toml;

  programs.git = {
    enable = true;
    userName = "kpango";
    userEmail = "yusukato@lycorp.co.jp";
    extraConfig.push.autoSetupRemote = true;
  };
}
```

## devShells

```nix
devShells.default = pkgs.mkShell {
  packages = with pkgs; [
    go gopls golangci-lint
    rustup rust-analyzer
    buf protobuf
    kubectl helm
  ];

  shellHook = ''
    export GOPATH=$HOME/go
    export PATH=$GOPATH/bin:$PATH
  '';

  CGO_ENABLED = "0";
};
```

## Common Commands

```bash
nix flake update                        # update all inputs
nix flake update nixpkgs               # update single input
nix build .#myapp                      # build flake output
nix develop                            # enter devShell
nix develop --command zsh              # enter with specific shell
home-manager switch --flake .#kpango   # apply home config
nix store gc                           # garbage collect old generations
nix flake check                        # validate flake outputs
nix search nixpkgs#<name>              # search packages
```

## Arch Linux + Nix Coexistence

```nix
# On Arch: install Nix (not NixOS) via the Determinate installer
# /nix/store is the store; system packages still come from pacman

# Use home-manager only — no system-level changes (don't manage /etc/ or systemd units, only ~/. paths)
# Prefer home.packages over system packages to avoid pacman conflicts
```

## macOS / nix-darwin Caveats

- `nix-darwin switch` / `darwin-rebuild` steps that need `sudo` cannot run through an agent's
  Bash tool (or `!`-prefixed shell): there is no tty, so password prompts hang. A GUI askpass
  (`osascript` dialog set as `SUDO_ASKPASS`, with a `sudo -A` wrapper prepended to `PATH`) can
  route the password through the OS instead of the agent.
- Beyond the tty issue, processes spawned this way also run with `launchctl managername ==
Background`, not `Aqua`. Some nix-darwin activation steps (e.g. App Management) require an
  Aqua session and refuse otherwise — this is a structural OS-level constraint with **no
  workaround**; it must be run from the user's actual terminal app.

## Anti-Patterns

- Don't use `with pkgs;` at top-level (pollutes scope, harder to grep)
- Don't pin `home.stateVersion` to a version you've never bootstrapped
- Don't mix flakes and non-flake inputs without `flake = false`
- Don't use `builtins.fetchTarball` in flakes — use `fetchFromGitHub` with a hash
- Don't verify package existence with `nix eval nixpkgs#<pkg>` — it resolves against the
  unpinned flake **registry** (always latest), not your `flake.lock` revision, and can give
  false positives/negatives against what actually builds. Verify against the pinned input:
  `nix eval --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.<system>.<pkg>.name'`
  (or `nix build` the real output). A pinned-vs-not verdict can also go stale after the next
  `flake.lock` update — re-verify rather than trusting a previously recorded verdict.
- Don't trust a package's `meta.platforms` as proof it actually works on that platform —
  it's a self-declared attribute that a hard dependency deep in the closure (only surfaces at
  `nix build` / instantiation, not `nix eval` on the attribute alone) or a missing runtime
  counterpart (e.g. an IPC client with nothing to talk to on that OS) can silently contradict.
  Check both build success and "does it have something to actually communicate with" before
  porting a platform-gated tool.
- Don't add two packages that provide the same binary name (e.g. `gotools`+`gopls` both ship
  `bin/modernize`, `clang`+`gcc` both ship `bin/c++`) to the same `home.packages` without
  checking — `pkgs.buildEnv` fails with "conflicting subpath". `lib.lowPrio` can tie with a
  package's existing default priority (clang-wrapper already defaults to 10, the same value
  `lowPrio` sets) and silently fail to resolve the conflict — read the actual values by running
  `nix eval` with `--apply` over your config's `home.packages` and their `meta.priority`
  (the attribute prefix differs per host: `homeConfigurations.<name>.config` standalone vs
  `darwinConfigurations.<host>.config.home-manager.users.<user>` /
  `nixosConfigurations.<host>....` when home-manager is a module), then use
  `lib.setPrio <explicit number>` on one side, or drop the redundant package.
