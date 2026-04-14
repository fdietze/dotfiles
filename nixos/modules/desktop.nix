{
  lib,
  ...
}: {
  options.my = {
    desktop = lib.mkOption {
      type = lib.types.enum [
        "gnome"
        "herbstluftwm"
      ];
      default = "gnome";
      example = "herbstluftwm";
      description = "Desktop environment/session to configure across NixOS and Home Manager.";
    };

    theme = lib.mkOption {
      type = lib.types.enum [
        "dark"
        "light"
      ];
      default = "dark";
      example = "light";
      description = "Theme polarity to configure across NixOS and Home Manager.";
    };
  };
}
