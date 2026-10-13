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
#     Removed together with the `graphify` package itself. No other package
#     in this flake depends on either attribute (confirmed by grep before
#     removal).
#
#   go — `final.go_1_27` (not the default top-level `go`, which still
#     resolves to `go_1_26` at this pinned nixpkgs revision) so that
#     `modules/home/packages/shared.nix`'s plain `go` package satisfies
#     go.mod files declaring `go 1.27.0`. `go_1_27` is a real GA release
#     (verified via `nix eval …pkgs.go_1_27.version` — no `rc`/`beta` suffix),
#     not the pre-release that existed at earlier nixpkgs revisions.
#
#   golangci-lint — Two independent overrides are layered here:
#
#       1. `override { buildGo127Module = prev.buildGoModule.override { go = final.go; }; }`
#          swaps the builder nixpkgs' package.nix pins for one that resolves
#          to `final.go` (the same derivation `modules/home/packages/shared.nix`
#          installs and the `go` override above sets). `prev.buildGoModule`
#          alone is NOT the go-agnostic generic builder it looks like —
#          nixpkgs' `all-packages.nix` defines `buildGoModule = buildGo126Module;`
#          (a fixed alias, "the unversioned attributes should always point to
#          the same go version"), so passing it through unmodified would
#          silently re-pin golangci-lint to go 1.26 regardless of what `go`
#          this overlay sets — the explicit `.override { go = final.go; }` is
#          required to actually make a `go` version bump here force a
#          golangci-lint rebuild (verified via `nix eval
#          …pkgs.golangci-lint.go.version == pkgs.go.version`).
#          The `buildGoNNNModule` parameter name itself tracks nixpkgs'
#          package.nix and has already changed once (`buildGo126Module` →
#          `buildGo127Module`, when nixpkgs bumped its own pinned default
#          builder from go 1.26 to go 1.27) — a `nix build` failure of the
#          form "called with unexpected argument 'buildGoNNNModule' … Did you
#          mean buildGoMMMModule?" after a nixpkgs bump means this literal
#          needs updating to match again.
#       2. `.overrideAttrs` bumps `version`/`src`/`vendorHash` to track
#          golangci-lint's own latest upstream release instead of waiting on
#          nixpkgs' package.nix to catch up. Currently a no-op in practice —
#          nixpkgs' own package.nix already carries the identical
#          version/src hash/vendorHash (both are `v2.13.2`, verified
#          2026-09-18) — but kept so this overlay stays the single source of
#          truth per CONTEXT.md Invariant-1, and so the next time
#          nixpkgs lags behind a new upstream golangci-lint tag, only this
#          block needs a version/hash bump (see CONTEXT.md's
#          "バージョン更新の運用" for the fakeHash procedure).
#          `ldflags` and `meta.changelog` are re-specified because they embed
#          `finalAttrs.version`, which does not re-resolve across
#          `overrideAttrs` — leaving them as `old.*` would keep baking in the
#          previous version string.
#
#     Trade-off accepted: this is a go × golangci-lint combination nixpkgs
#     has not itself validated. If a future `go` bump breaks golangci-lint's
#     build or type-checker API compatibility, fix it here (patch, or a
#     temporary pin back to a specific `buildGoNNNModule`) rather than
#     reverting silently.
#
# prmt is overridden below to skip its checkPhase; lumen needs no override,
# it substitutes cleanly from cache.nixos.org at the pinned revision (see above).
[
  (
    final: prev:
    let
      golangciLintVersion = "2.13.2";
    in
    {
      # See the file-header comment above for why `go_1_27` (not the default
      # top-level `go`) is selected here.
      go = final.go_1_27;
      neovim = prev.neovim.override {
        withPython3 = true;
        withRuby = true;
        vimAlias = true;
      };
      golangci-lint =
        (prev.golangci-lint.override {
          buildGo127Module = prev.buildGoModule.override { go = final.go; };
        }).overrideAttrs
          (old: {
            version = golangciLintVersion;
            src = prev.fetchFromGitHub {
              owner = "golangci";
              repo = "golangci-lint";
              tag = "v${golangciLintVersion}";
              hash = "sha256-RbWKPIG+UK82S9W9tp/CciZ669vudh95VOfHfdQWx3M=";
            };
            vendorHash = "sha256-R83GeyfuZ+w30jZqFGYi0yua8E1Ey2q7/OlVmw8zDCg=";
            ldflags = [
              "-s"
              "-w"
              "-X main.version=${golangciLintVersion}"
              "-X main.commit=v${golangciLintVersion}"
              "-X main.date=1970-01-01T00:00:00Z"
            ];
            meta = old.meta // {
              changelog = "https://github.com/golangci/golangci-lint/blob/v${golangciLintVersion}/CHANGELOG.md";
            };
          });
      prmt = prev.prmt.overrideAttrs (_old: {
        doCheck = false;
      });
    }
  )
]
