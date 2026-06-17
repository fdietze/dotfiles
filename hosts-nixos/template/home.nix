# Home Manager für den Fallback-Host: nur der portable Shell-Core plus die
# standalone-Essentials (git), kein Desktop. Wer den Host behält, kann hier
# Desktop-Module wie in hosts-nixos/gurke/home.nix ergänzen.
{...}: {
  imports = [
    ../../modules/home-manager/profiles/shell-core.nix
    ../../modules/home-manager/profiles/standalone-extras.nix
  ];
}
