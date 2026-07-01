{
  lib,
  rustPlatform,
  fetchCrate,
}:

rustPlatform.buildRustPackage rec {
  pname = "lumen";
  version = "2.30.0";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  meta = with lib; {
    description = "AI-powered CLI tool for git commit summaries and interactive diff viewer";
    homepage = "https://github.com/jnsahaj/lumen";
    mainProgram = "lumen";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mit;
  };
}
