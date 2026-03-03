{
  description = "macOS Development Environment Flake (Apple Silicon)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, darwin, nixpkgs, home-manager, ... }:
    let
      # Use an environment variable or default to the user running the command if username isn't set
      username = builtins.getEnv "USER";
    in
    {
      # Assuming 'macbook' is the hostname of the target Apple Silicon Mac.
      darwinConfigurations."macbook" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        # Passing specialArgs to modules (configuration.nix, home.nix, etc.)
        specialArgs = { inherit inputs username; };
        modules = [
          ./configuration.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Passing specialArgs to Home Manager as well
            home-manager.extraSpecialArgs = { inherit inputs username; };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    };
}
