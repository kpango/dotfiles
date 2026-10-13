{
  username,
  versions,
  homeDirectory,
  ...
}:

{
  imports = [
    ./shared.nix
    ./linux.nix
    ./darwin.nix
  ];

  home = {
    inherit username homeDirectory;
    stateVersion = versions.homeManager;
  };
}
