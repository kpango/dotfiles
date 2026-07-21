{ rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "prmt";
  version = "0.5.0";
  src = fetchFromGitHub {
    owner = "3axap4eHko";
    repo = "prmt";
    rev = "v${version}";
    hash = "sha256-yDYJMEtiGRCPRJksVKgZMdvX8jSTKZV4GEz4W5DmoRU=";
  };
  cargoHash = "sha256-47Lg1hmuSI37Bi+wWoxy+YxJqdrXXPvmxYvhN0D1UXo=";
  buildFeatures = [ "git-gix" ];
  doCheck = false; # git-related tests fail in Nix sandbox (no git binary available)
}
