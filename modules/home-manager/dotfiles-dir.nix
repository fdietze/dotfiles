# Single source for the dotfiles checkout path. Anticipates moving the repo out
# of ~/projects: change the default here, every consumer follows. Home-manager
# `my.*` tree (separate from the nixos `my.*` in modules/options.nix).
{
  config,
  lib,
  ...
}: {
  options.my.dotfilesDir = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/projects/dotfiles";
    description = "Absolute path to the dotfiles git checkout on this host.";
  };
}
