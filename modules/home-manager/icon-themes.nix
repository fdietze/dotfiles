{
  desktop,
  lib,
  pkgs,
  theme,
  ...
}:
let
  desktopRegistry = import ../desktop-registry.nix;
  hasThemeVariants = builtins.elem desktop desktopRegistry.themedDesktops;
  iconThemeName =
    if theme == "dark"
    then "Papirus-Dark"
    else "Papirus";
in
lib.mkIf hasThemeVariants {
  gtk.iconTheme = {
    name = iconThemeName;
    package = pkgs.papirus-icon-theme;
  };

  qt.qt6ctSettings.Appearance.icon_theme = iconThemeName;
}
