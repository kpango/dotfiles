{
  # This file contains overlays to modify existing packages in nixpkgs.
  # For example, applying patches, overriding versions, or adding features.
  
  # Example:
  # my-overlay = final: prev: {
  #   # Override a package
  #   hello = prev.hello.overrideAttrs (old: {
  #     patches = (old.patches or []) ++ [ ./my-patch.patch ];
  #   });
  # };
}
