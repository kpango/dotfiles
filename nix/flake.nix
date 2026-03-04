{
  description = "Cross-platform Nix Configuration for macOS and NixOS (Desktop/Laptop)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # macOS Specific
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, darwin, home-manager, ... }:
    let
      # Use a statically defined username to avoid pure evaluation errors with builtins.getEnv
      username = "kpango";

      # Import centrally managed versions
      versions = import ./core/versions.nix;

      # Shared Home Manager setup block to avoid duplication
      mkHomeManagerBlock = hostname: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = {
            inherit inputs username hostname versions;
          };
          users.${username} = import ./profiles/home.nix;
        };
      };

      mkNixosSystem = hostname: extraModules: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs username hostname versions;
        };
        modules = [
          ./profiles/nixos-configuration.nix
          home-manager.nixosModules.home-manager
          (mkHomeManagerBlock hostname)
        ] ++ extraModules;
      };

      mkDarwinSystem = hostname: extraModules: darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs username hostname versions;
        };
        modules = [
          ./profiles/configuration.nix
          home-manager.darwinModules.home-manager
          (mkHomeManagerBlock hostname)
        ] ++ extraModules;
      };

    in
    {
      # macOS Apple Silicon Configurations (M1/M4)
      darwinConfigurations = {
        "macbook" = mkDarwinSystem "macbook" [];
      };

      # Generic NixOS Configurations based on Arch dotfiles
      nixosConfigurations = {
        # Desktop profile (NVIDIA Desktop)
        "desk" = mkNixosSystem "desk" [
          ./hosts/desk/hardware.nix
        ];

        # Laptop profile (ThinkPad P1 - NVIDIA Optimus)
        "thinkpad-p1" = mkNixosSystem "thinkpad-p1" [
          ./hosts/thinkpad-p1/hardware.nix
        ];

        # Laptop profile (ThinkPad X1 Carbon Gen6 - Intel iGPU)
        "thinkpad-x1" = mkNixosSystem "thinkpad-x1" [
          ./hosts/thinkpad-x1/hardware.nix
        ];
      };
    };
}
