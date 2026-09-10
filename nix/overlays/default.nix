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
#   datamodel-code-generator — a build-time-only Python tool pulled in
#     transitively by several python3.14Packages.python-tree-sitter-* packages
#     (which graphify depends on). Its own test suite fails at this pinned
#     nixpkgs revision (verified 2026-08-06, still failing 2 days later after
#     bumping nixpkgs from 2026-08-02 to 2026-08-04): tests/main/test_main_general.py
#     ::test_ruff_check_and_format_combined and ::test_ruff_check_only both
#     fail on an exact-output-match assertion against a fixture that expects
#     no blank line after `from __future__ import annotations`, while the
#     `ruff` version bundled at this revision emits one — a pinned-fixture vs.
#     ruff-version mismatch inside datamodel-code-generator's own test suite,
#     unrelated to its actual codegen output correctness (2619+ other tests
#     pass). Disabled via doCheck rather than waiting on a nixpkgs bump since
#     neither datamodel-code-generator nor ruff moved versions in that window.
#     Must go through pythonPackagesExtensions (not a plain top-level
#     override) so every python3.NNPackages set — and anything else in that
#     set that depends on datamodel-code-generator — picks up the same
#     unpatched build.
#
#   python3Packages.tree-sitter-grammars.* — graphify's actual grammar
#     dependencies live at this nested attribute path (see
#     pkgs/by-name/gr/graphify/package.nix: `python3.pkgs.tree-sitter-grammars.
#     tree-sitter-<lang>`), not at a top-level `python3.14Packages.tree-sitter-
#     <lang>` (a same-named but unrelated attribute, when it exists at all).
#     Found via the tree-sitter-c-sharp case above, then confirmed systemic by
#     checking all 21 languages graphify depends on directly with `nix
#     derivation show`: every single one has internal pname
#     "python-tree-sitter-<lang>" while its installed .dist-info metadata is
#     registered as "tree-sitter-<lang>" (no "python-" prefix, matching the
#     upstream PyPI distribution name) — a systemic bug in whatever generator
#     nixpkgs uses to build the tree-sitter-grammars set, not specific to any
#     one language. `pythonMetadataCheckPhase` (pkgs/development/interpreters/
#     python/hooks/python-metadata-check-hook.sh) calls
#     `importlib.metadata.version(derivationPname)` and gets
#     PackageNotFoundError since no dist-info is registered under the
#     "python-"-prefixed name. Runs independently of `doCheck` (confirmed
#     doCheck was already "" i.e. false and it still failed) — the hook's own
#     escape hatch is the `dontCheckPythonMetadata` env var, applied
#     generically below via mapAttrs rather than enumerated by name so any
#     future addition to tree-sitter-grammars inherits the fix too.
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
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pyFinal: pyPrev: {
        datamodel-code-generator = pyPrev.datamodel-code-generator.overridePythonAttrs (_old: {
          doCheck = false;
        });
        tree-sitter-grammars = builtins.mapAttrs (
          _name: pkg:
          if pkg ? overridePythonAttrs then
            pkg.overridePythonAttrs (_old: {
              dontCheckPythonMetadata = true;
            })
          else
            pkg
        ) pyPrev.tree-sitter-grammars;
      })
    ];
  })
]
