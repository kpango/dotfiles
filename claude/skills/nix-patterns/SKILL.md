---
name: nix-patterns
description: Nix flakes, derivations, overlays, home-manager, devShells, and nixpkgs patterns for reproducible system configuration and development environments.
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

# Use home-manager only — no system-level changes
# Don't manage /etc/ or systemd system units — only ~/. paths
# Prefer home.packages over system packages to avoid pacman conflicts
```

## Anti-Patterns

- Don't use `with pkgs;` at top-level (pollutes scope, harder to grep)
- Don't pin `home.stateVersion` to a version you've never bootstrapped
- Don't mix flakes and non-flake inputs without `flake = false`
- Don't use `builtins.fetchTarball` in flakes — use `fetchFromGitHub` with a hash
