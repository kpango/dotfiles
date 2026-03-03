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

      mkNixosSystem = hostname: extraModules: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs username hostname; };
        modules = [
          ./nixos-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs username hostname; };
            home-manager.users.${username} = import ./home.nix;
          }
        ] ++ extraModules;
      };
    in
    {
      # macOS Apple Silicon Configuration
      darwinConfigurations."macbook" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs username; hostname = "macbook"; };
        modules = [
          ./configuration.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs username; hostname = "macbook"; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };

      # Generic NixOS Configurations based on Arch dotfiles
      nixosConfigurations = {
        # Desktop profile
        "desk" = mkNixosSystem "desk" [
        ];

        # Laptop profile (ThinkPad P1/X1 style)
        "laptop" = mkNixosSystem "laptop" [
        ];
      };
    };
}
