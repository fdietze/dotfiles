{
  lib,
  ...
}:
let
  desktopRegistry = import ./desktop-registry.nix;
in
{
  options.my = {
    desktop = lib.mkOption {
      type = lib.types.enum desktopRegistry.desktops;
      default = "gnome";
      example = "herbstluftwm";
      description = "Desktop environment/session to configure across NixOS and Home Manager.";
    };

    theme = lib.mkOption {
      type = lib.types.enum desktopRegistry.themes;
      default = "dark";
      example = "light";
      description = "Theme polarity to configure across NixOS and Home Manager.";
    };
  };
}
