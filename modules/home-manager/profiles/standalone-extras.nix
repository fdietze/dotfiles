# Essentials für standalone/Template Home Manager, die auf einem vollwertigen
# NixOS-Host vom System kommen (environment.systemPackages) und daher nicht im
# shell-core stehen — sonst würden sie gurkes home-path verändern. Hier nur für
# Kontexte ohne solchen System-Layer (homeConfigurations, Template-Host).
{pkgs, ...}: {
  # git ist die Grundlage des ganzen Workflows (tig, lazygit, die g-Aliases);
  # die Konfiguration kommt aus dotfiles.nix (~/.gitconfig), nur das Binary fehlt.
  home.packages = [pkgs.git];
}
