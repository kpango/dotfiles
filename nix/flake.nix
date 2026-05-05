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

    # Dotfiles repository root (one level above nix/).
    # Using a path input makes the repo root a Nix store path, which is
    # accessible in pure evaluation mode — eliminating the need for
    # hardcoded absolute host paths in dotfilesPath.
    dotfiles-root = {
      url = "path:..";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, darwin, home-manager, dotfiles-root, ... }:
    let
      # Import centrally managed settings and versions
      settings = import ./core/settings.nix;
      versions = import ./core/versions.nix;

      inherit (settings) username;

      # Repo root as a Nix store path — works in pure eval mode on any machine.
      dotfilesPath = "${dotfiles-root}";

      # Shared Home Manager setup block.
      # isDarwinHost is passed explicitly rather than inferred from dotfilesPath,
      # because make nix/setup sets both dotfilesDir.linux and dotfilesDir.darwin
      # to the same absolute path, making path-comparison-based detection unreliable.
      mkHomeManagerBlock = hostname: isDarwinHost:
        let
          homeDirectory =
            if isDarwinHost
            then "${settings.homeDirectories.darwin}/${username}"
            else "${settings.homeDirectories.linux}/${username}";
        in
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit inputs username hostname versions settings dotfilesPath homeDirectory;
              isDarwin = isDarwinHost;
              isLinux = !isDarwinHost;
            };
            users.${username} = import ./modules/home;
          };
        };

      mkNixosSystem = hostname: extraModules: nixpkgs.lib.nixosSystem {
        system = settings.system.linux;
        specialArgs = {
          inherit inputs username hostname versions settings dotfilesPath;
          isDarwin = false;
          isLinux = true;
          homeDirectory = "${settings.homeDirectories.linux}/${username}";
        };
        modules = [
          { nixpkgs.pkgs = mkPkgs settings.system.linux; }
          ./modules/nixos
          home-manager.nixosModules.home-manager
          (mkHomeManagerBlock hostname false)
        ] ++ extraModules;
      };

      mkDarwinSystem = hostname: extraModules: darwin.lib.darwinSystem {
        system = settings.system.darwin;
        specialArgs = {
          inherit inputs username hostname versions settings dotfilesPath;
          isDarwin = true;
          isLinux = false;
          homeDirectory = "${settings.homeDirectories.darwin}/${username}";
        };
        modules = [
          { nixpkgs.pkgs = mkPkgs settings.system.darwin; }
          ./modules/darwin
          home-manager.darwinModules.home-manager
          (mkHomeManagerBlock hostname true)
        ] ++ extraModules;
      };

      # Instantiate nixpkgs with overlays and allowUnfree for a given system
      mkPkgs = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = import ./overlays;
      };

    in
    {
      # macOS Apple Silicon Configurations
      darwinConfigurations = nixpkgs.lib.genAttrs [
        "macbook-air-m1"
        "macbook-pro-m3"
      ]
        (hostname: mkDarwinSystem hostname [ ]);

      # NixOS Configurations — short attribute name, full real hostname
      nixosConfigurations = {
        p1 = mkNixosSystem "thinkpad-p1-gen5" [ ./hosts/p1 ];
        x1 = mkNixosSystem "thinkpad-x1-gen9" [ ./hosts/x1 ];
        g2 = mkNixosSystem "hp-dragonfly-g2" [ ./hosts/g2 ];
      } // {

        # ── Threadripper workstation (tr) ────────────────────────────────────
        # AMD Ryzen Threadripper 3990X, 251 GB RAM
        # Dual Intel X710 10GbE bonded LACP, NVIDIA GPU, NVMe RAID0
        # Self-contained modules under nix/modules/{hardware,networking,system,...}
        tr = nixpkgs.lib.nixosSystem {
          system = settings.system.linux;
          specialArgs = {
            inherit inputs username versions settings dotfilesPath;
            hostname = "desk-threadripper";
            isDarwin = false;
            isLinux = true;
            homeDirectory = "${settings.homeDirectories.linux}/${username}";
          };
          modules = [
            { nixpkgs.pkgs = mkPkgs settings.system.linux; }
            ./hosts/tr
            home-manager.nixosModules.home-manager
            (mkHomeManagerBlock "desk-threadripper" false)
          ];
        };
      };

      # Add standard formatter (nixpkgs-fmt)
      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ]
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

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
