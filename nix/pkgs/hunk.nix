{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation rec {
  pname = "hunk";
  version = "0.12.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/hunkdiff-linux-x64/-/hunkdiff-linux-x64-${version}.tgz";
    hash = "sha256-4IRCpr+nnAe1HgrYMgAy9uP+EMtSKTYiny326k4UcG8=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 bin/hunk $out/bin/hunk
    runHook postInstall
  '';

  meta = with lib; {
    description = "Terminal diff viewer for understanding agent-authored changesets";
    mainProgram = "hunk";
    platforms = [ "x86_64-linux" ];
    license = licenses.mit;
  };
}
