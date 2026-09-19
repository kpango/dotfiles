# overlays/default.nix — returns a list of overlays for use in mkPkgs
#
# There used to be a nix/pkgs/ directory holding two hand-written packages, plus
# a `packages` flake output exposing them. Both are gone: nixpkgs ships (or
# shipped) them, at newer versions, and each local copy had already broken once.
#
#   lumen — was overridden here. The local pkgs/lumen.nix still carried
#     `sha256-AAAA…` placeholders for both its src hash and cargoHash, which is
#     what made the `NixOS build` CI job fail on every run. nixpkgs' own
#     jnsahaj/lumen (2.32.0) was the replacement, BUT it turned out to not
#     exist yet at this flake's pinned nixpkgs revision (`nix eval` against the
#     flake's own `inputs.nixpkgs` throws `attribute 'lumen' missing`, even
#     though the flake registry's always-current nixpkgs has it — the registry
#     is not the same nixpkgs as the one actually used to build). Every
#     `pkgs.lumen` reference was removed (nixos/core/programs.nix and
#     modules/home/packages/shared.nix) until the flake's nixpkgs input got
#     bumped past whenever lumen was added upstream.
#
#     Re-added 2026-08-06: flake.lock now pins a nixpkgs revision (2026-08-05,
#     rev 643809054d65fdd466a63e3155b8c498cb483c04) where `pkgs.lumen` does
#     resolve — reverify with `nix eval --impure --expr '(import
#     (builtins.getFlake "path:$PWD").inputs.nixpkgs { system =
#     "aarch64-darwin"; }).lumen.pname'` (needs `NIX_REMOTE=local?root=<scratch>`
#     in a single-user/no-daemon shell) directly against the flake's own
#     `inputs.nixpkgs`, NOT `nix eval nixpkgs#lumen` against the registry — the
#     registry gave a false positive the first time this was checked. It now
#     lives in modules/home/packages/shared.nix next to prmt.
#
#   prmt — was called directly from modules/home/packages/shared.nix. It built
#     from source, so fetchCargoVendor had to reach crates.io during the build,
#     which fails behind a TLS-intercepting proxy: the build sandbox uses
#     nixpkgs' `cacert` bundle and cannot see a corporate root CA. nixpkgs has
#     3axap4eHko/prmt at 0.7.0, prebuilt in the binary cache, and unlike lumen
#     this one does exist at the pinned revision (build-tested).
#
#     When the cache doesn't substitute it (observed on aarch64-darwin: cache
#     reachable, but this exact revision's output isn't cached for that
#     platform) it falls back to a local build, whose checkPhase runs 2 tests
#     (modules::path::tests::relative_path_inside_home_renders_tilde and
#     ..._with_shared_prefix_is_not_tilde) that create real directories under
#     $HOME — always "Read-only file system" inside the Nix build sandbox,
#     unrelated to prmt's actual CLI behaviour (all other 82 tests pass).
#     Disabled here rather than upstream since the crate isn't vendored here.
#
#   datamodel-code-generator / python3Packages.tree-sitter-grammars.* — these two
#     pythonPackagesExtensions overrides existed solely to work around build/metadata
#     bugs in graphify's own transitive Python dependencies (a build-time
#     datamodel-code-generator test-fixture mismatch, and a tree-sitter-grammars
#     dist-info naming bug across the 21 grammar languages graphify depended on).
#     Removed together with the `graphify` package itself — see
#     docs/adr/ADR-0002-graft-graphify-consolidation.md. No other package in this
#     flake depends on either attribute (confirmed by grep before removal).
#
# prmt is overridden below to skip its checkPhase; lumen needs no override,
# it substitutes cleanly from cache.nixos.org at the pinned revision (see above).
[
  (_final: prev: {
    neovim = prev.neovim.override {
      withPython3 = true;
      withRuby = true;
      vimAlias = true;
    };
    prmt = prev.prmt.overrideAttrs (_old: {
      doCheck = false;
    });
  })
]
