# Paseo Linux Desktop App (Electron GUI)
# Erlaubt die grafische Verwaltung deiner Agents. Verbindet sich lokal oder
# remote (z.B. zu cubie) über dein Tailnet.
{
  pkgs,
  flake-inputs,
  ...
}: {
  home.packages = [
    flake-inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.desktop
  ];
}
