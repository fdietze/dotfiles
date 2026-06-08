# Generischer, desktop-freier Fallback-Host für noch nicht konfigurierte
# Maschinen. scripts/setup-new-host.sh kopiert hosts/template/ nach
# hosts/<hostname>/, erzeugt dort hardware-configuration.nix via
# `nixos-generate-config --show-hardware-config` und legt eine system-Datei mit
# der erkannten Architektur an. Wer den Host behalten will, ergänzt Desktops und
# eine local.nix analog zu hosts/gurke/.
#
# Auto-Discovery in flake.nix überspringt "template", daher wird dieses
# Verzeichnis nie selbst zu einer nixosConfiguration ausgewertet.
{
  pkgs,
  lib,
  flake-inputs,
  uiFonts,
  ...
}: {
  # Flakes dauerhaft aktiv, damit `nixos-rebuild --flake` direkt funktioniert.
  nix.settings.experimental-features = ["nix-command" "flakes"];
  # shell-core zieht über packages-cli/Aliases unfreie Pakete (unrar, claude-code).
  nixpkgs.config.allowUnfree = true;

  # UEFI-Default; auf BIOS-only-Maschinen nach dem Kopieren anpassen.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  users.users.felix = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # Home Manager bekommt dieselben Args wie auf definierten Hosts, damit der
  # shell-core (nvf) ohne Desktop-Spezialisierung baut. Kein my.desktop/my.theme:
  # der Template-Host hat keinen Desktop, daher der neutrale Default theme="dark".
  home-manager.extraSpecialArgs = {
    inherit flake-inputs uiFonts;
    nvf = flake-inputs.nvf;
    theme = "dark";
  };

  # Mit dem Kopier-Zeitpunkt mitwandernder Default; bei Bedarf am neuen Host
  # auf die installierte Release-Version setzen.
  system.stateVersion = lib.mkDefault "26.05";
}
