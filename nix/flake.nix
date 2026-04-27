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
      # Import centrally managed settings and versions
      settings = import ./core/settings.nix;
      versions = import ./core/versions.nix;
      
      inherit (settings) username;

      # Shared Home Manager setup block to avoid duplication
      mkHomeManagerBlock = hostname: dotfilesPath: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = {
            inherit inputs username hostname versions settings dotfilesPath;
            isDarwin = dotfilesPath == settings.dotfilesDir.darwin;
            isLinux = dotfilesPath == settings.dotfilesDir.linux;
            homeDirectory = if (dotfilesPath == settings.dotfilesDir.darwin) then "${settings.homeDirectories.darwin}/${username}" else "${settings.homeDirectories.linux}/${username}";
          };
          users.${username} = import ./modules/home;
        };
      };

      mkNixosSystem = hostname: extraModules: nixpkgs.lib.nixosSystem {
        system = settings.system.linux;
        specialArgs = {
          inherit inputs username hostname versions settings;
          isDarwin = false;
          isLinux = true;
          dotfilesPath = settings.dotfilesDir.linux;
          homeDirectory = "${settings.homeDirectories.linux}/${username}";
        };
        modules = [
          { nixpkgs.pkgs = mkPkgs settings.system.linux; }
          ./modules/nixos
          home-manager.nixosModules.home-manager
          (mkHomeManagerBlock hostname settings.dotfilesDir.linux)
        ] ++ extraModules;
      };

      mkDarwinSystem = hostname: extraModules: darwin.lib.darwinSystem {
        system = settings.system.darwin;
        specialArgs = {
          inherit inputs username hostname versions settings;
          isDarwin = true;
          isLinux = false;
          dotfilesPath = settings.dotfilesDir.darwin;
          homeDirectory = "${settings.homeDirectories.darwin}/${username}";
        };
        modules = [
          { nixpkgs.pkgs = mkPkgs settings.system.darwin; }
          ./modules/darwin
          home-manager.darwinModules.home-manager
          (mkHomeManagerBlock hostname settings.dotfilesDir.darwin)
        ] ++ extraModules;
      };

    in
    {
      # macOS Apple Silicon Configurations
      darwinConfigurations = nixpkgs.lib.genAttrs [
        "macbook-air-m1"
        "macbook-pro-m3"
      ] (hostname: mkDarwinSystem hostname []);

      # Generic NixOS Configurations based on Arch dotfiles
      nixosConfigurations = nixpkgs.lib.genAttrs [
        "desk-threadripper"
        "thinkpad-p1-gen5"
        "thinkpad-x1-gen9"
        "hp-dragonfly-g2"
      ] (hostname: mkNixosSystem hostname [
        ./hosts/${hostname}
      ]);

      # Add standard formatter (nixpkgs-fmt)
      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ] (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      # Custom packages
      packages = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (system: 
        import ./pkgs { pkgs = mkPkgs system; }
      );

      # Development shells for repository management
      devShells = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            name = "dotfiles-shell";
            buildInputs = with pkgs; [
              nixpkgs-fmt
              statix # Lints and suggestions for the Nix language
              deadnix # Find and remove unused code in .nix source files
              git
            ];
            shellHook = ''
              echo "❄️ Welcome to the dotfiles development shell ❄️"
              echo "Tools available:"
              echo "  - nixpkgs-fmt: Format Nix files"
              echo "  - statix: Lint Nix files (run 'statix check')"
              echo "  - deadnix: Find unused code (run 'deadnix .')"
            '';
          };
        }
      );
    };
}
