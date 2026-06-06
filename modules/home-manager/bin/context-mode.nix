{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bun,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "context-mode";
  version = "1.0.151";

  src = fetchurl {
    url = "https://registry.npmjs.org/context-mode/-/context-mode-${finalAttrs.version}.tgz";
    hash = "sha512-wV8gciRMOpR8bOsZO79KpHm6EbSQ/qBOCZUx2vSH6FwZroubVs4CWDldESOVpZZaJJWinFQ+ruK1kJjWmhvMIA==";
  };

  nativeBuildInputs = [makeWrapper];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/context-mode"
    cp -R . "$out/lib/context-mode"

    makeWrapper ${lib.getExe bun} "$out/bin/context-mode" \
      --prefix PATH : ${lib.makeBinPath [bun]} \
      --add-flags "$out/lib/context-mode/cli.bundle.mjs"

    runHook postInstall
  '';

  meta = {
    description = "MCP plugin for sandboxed execution, searchable output, and context-window savings";
    homepage = "https://github.com/mksglu/context-mode";
    license = lib.licenses.elastic20;
    mainProgram = "context-mode";
    platforms = lib.platforms.linux;
  };
})
