# Portabler, headless-tauglicher Home-Manager-Core. Wird sowohl von shared.nix
# (volle Desktop-Konfiguration) als auch standalone (homeConfigurations,
# Template-Host) importiert. Enthält nur desktop-unabhängige Module und
# Shell-Essentials. Default-Theme "dark"; kein stylix, keine GUI-Terminals.
{...}: {
  imports = [
    ../shell.nix
    ../dotfiles.nix
    ../git.nix
    ../yazi.nix
    ./packages-cli.nix
    ../nvf.nix
  ];
}
