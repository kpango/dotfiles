# overlays/default.nix — returns a list of overlays for use in mkPkgs
[
  (final: prev: {
    neovim = prev.neovim.override {
      withPython3 = true;
      withRuby = true;
      vimAlias = true;
    };
  })
]
