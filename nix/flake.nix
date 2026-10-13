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

    # apple/container (aarch64-darwin only) — packages the signed .pkg release via Nix
    # and manages the Kata Linux kernel as a derivation instead of an ad-hoc curl+installer
    # step. See modules/darwin/containerization.nix for the services.containerization wiring.
    nix-apple-container.url = "github:halfwhey/nix-apple-container";
    nix-apple-container.inputs.nixpkgs.follows = "nixpkgs";

    # Dotfiles repository root (one level above nix/).
    # Using a path input makes the repo root a Nix store path, which is
    # accessible in pure evaluation mode — eliminating the need for
    # hardcoded absolute host paths in dotfilesPath.
    dotfiles-root = {
      url = "path:..";
      flake = false;
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      darwin,
      home-manager,
      dotfiles-root,
      ...
    }:
    let
      # Import centrally managed settings and versions
      settings = import ./core/settings.nix;
      versions = import ./core/versions.nix;

      inherit (settings) username;

      # Repo root as a Nix store path — works in pure eval mode on any machine.
      dotfilesPath = "${dotfiles-root}";

      # Shared Home Manager setup block.
      # isDarwinHost is passed explicitly rather than inferred from dotfilesPath
      # (which is the same store path on every platform, so it carries no
      # platform information to infer from).
      #
      # `user` is the local account name to manage. It defaults to settings.username
      # at every call site except hosts whose local account differs (see
      # darwinConfigurations.macbook-pro-m1).
      mkHomeManagerBlock =
        hostname: isDarwinHost: user:
        let
          homeDirectory =
            if isDarwinHost then
              "${settings.homeDirectories.darwin}/${user}"
            else
              "${settings.homeDirectories.linux}/${user}";
        in
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # home-manager refuses to replace a file it did not create. On a first
            # activation that aborts the whole run — a Jamf-managed ~/.zshrc is
            # enough to stop it. Moving the original aside keeps activation
            # idempotent and leaves the previous file recoverable.
            backupFileExtension = "hm-bak";
            extraSpecialArgs = {
              inherit
                inputs
                hostname
                versions
                settings
                dotfilesPath
                homeDirectory
                ;
              username = user;
              isDarwin = isDarwinHost;
              isLinux = !isDarwinHost;
            };
            users.${user} = import ./modules/home;
          };
        };

      # `baseModules` defaults to the shared NixOS module set (./modules/nixos)
      # used by every generic desktop/laptop host (p1/x1/g2). The Threadripper
      # workstation (tr) hand-picks a smaller subset of those same shared
      # modules directly inside ./hosts/tr, rather than the full set, so it
      # passes `baseModules = [ ]` and relies entirely on `extraModules`.
      mkNixosSystem =
        {
          hostname,
          baseModules ? [ ./modules/nixos ],
          extraModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          system = settings.system.linux;
          specialArgs = {
            inherit
              inputs
              username
              hostname
              versions
              settings
              dotfilesPath
              ;
            isDarwin = false;
            isLinux = true;
            homeDirectory = "${settings.homeDirectories.linux}/${username}";
          };
          modules = [
            { nixpkgs.pkgs = mkPkgs settings.system.linux; }
          ]
          ++ baseModules
          ++ [
            home-manager.nixosModules.home-manager
            (mkHomeManagerBlock hostname false username)
          ]
          ++ extraModules;
        };

      # `user` overrides the local account name for hosts where it differs from
      # settings.username (work machines, shared laptops).
      mkDarwinSystem =
        {
          hostname,
          user ? username,
          extraModules ? [ ],
        }:
        darwin.lib.darwinSystem {
          system = settings.system.darwin;
          specialArgs = {
            inherit
              inputs
              hostname
              versions
              settings
              dotfilesPath
              ;
            username = user;
            isDarwin = true;
            isLinux = false;
            homeDirectory = "${settings.homeDirectories.darwin}/${user}";
          };
          modules = [
            { nixpkgs.pkgs = mkPkgs settings.system.darwin; }
            ./modules/darwin
            home-manager.darwinModules.home-manager
            (mkHomeManagerBlock hostname true user)
          ]
          ++ extraModules;
        };

      # Instantiate nixpkgs with overlays and allowUnfree for a given system
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = import ./overlays;
        };

    in
    {
      # macOS Apple Silicon Configurations
      darwinConfigurations =
        nixpkgs.lib.genAttrs [
          "macbook-air-m1"
          "macbook-pro-m3"
        ] (hostname: mkDarwinSystem { inherit hostname; })
        // {
          # MacBook Pro (Apple M1 Pro). Local account name differs from
          # settings.username, so home-manager is pointed at it explicitly.
          macbook-pro-m1 = mkDarwinSystem {
            hostname = "macbook-pro-m1";
            user = "yusukekato";
          };
        };

      # NixOS Configurations — short attribute name, full real hostname
      nixosConfigurations = {
        p1 = mkNixosSystem {
          hostname = "thinkpad-p1-gen5";
          extraModules = [ ./hosts/p1 ];
        };
        x1 = mkNixosSystem {
          hostname = "thinkpad-x1-gen9";
          extraModules = [ ./hosts/x1 ];
        };
        g2 = mkNixosSystem {
          hostname = "hp-dragonfly-g2";
          extraModules = [ ./hosts/g2 ];
        };

        # ── Threadripper workstation (tr) ────────────────────────────────────
        # AMD Ryzen Threadripper 3990X, 251 GB RAM
        # Dual Intel X710 10GbE bonded LACP, NVIDIA GPU, NVMe RAID0
        # Self-contained modules under nix/modules/{hardware,networking,system,...}
        # — hosts/tr/default.nix hand-picks the shared modules it wants, so
        # this passes baseModules = [ ] instead of the ./modules/nixos default.
        tr = mkNixosSystem {
          hostname = "desk-threadripper";
          baseModules = [ ];
          extraModules = [ ./hosts/tr ];
        };
      };

      # Add standard formatter (nixfmt-rfc-style)
      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ] (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      # No `packages` output: there are no hand-written packages any more. Both
      # that used to live in nix/pkgs/ are in nixpkgs now — see overlays/default.nix
      # for why each local copy was dropped.

      # Development shells for repository management
      devShells = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            name = "dotfiles-shell";
            buildInputs = with pkgs; [
              nixfmt-rfc-style
              statix # Lints and suggestions for the Nix language
              deadnix # Find and remove unused code in .nix source files
              git
            ];
            shellHook = ''
              echo "❄️ Welcome to the dotfiles development shell ❄️"
              echo "Tools available:"
              echo "  - nixfmt: Format Nix files"
              echo "  - statix: Lint Nix files (run 'statix check')"
              echo "  - deadnix: Find unused code (run 'deadnix .')"
            '';
          };
        }
      );
    };
}
