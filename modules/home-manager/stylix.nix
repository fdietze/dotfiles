{
  desktop,
  lib,
  ...
}: let
  desktopRegistry = import ../desktop-registry.nix;
  hasThemeVariants = builtins.elem desktop desktopRegistry.themedDesktops;
in
  lib.mkIf hasThemeVariants {
    stylix = {
      autoEnable = false;
      targets = {
        rofi.enable = false;
        neovim.enable = false;
        nvf.enable = false;
        qt.enable = true;
        alacritty.enable = true;
        kitty.enable = true;
        wezterm.enable = true;
        gtk.enable = true;
      };
    };
  }
