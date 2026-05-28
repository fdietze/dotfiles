{
  config,
  lib,
  uiFonts,
  ...
}: let
  desktopRegistry = import ../desktop-registry.nix;
  base16 = import ../themes/base16.nix;
  isThemed = builtins.elem config.my.desktop desktopRegistry.themedDesktops;
in {
  # Stylix is enabled unconditionally so its home-manager auto-wire always
  # declares the stylix.* HM option path. Themed desktops opt their targets
  # in via the `targets` block below; unthemed desktops (noctalia-niri) leave
  # all targets off and own GTK/Qt theming themselves (nwg-look, qt6ct).
  # https://stylix.danth.me/index.html
  stylix = {
    enable = true;
    autoEnable = false;
    polarity = "dark";
    fonts = {
      serif = {
        package = uiFonts.serif.package;
        name = uiFonts.serif.name;
      };
      sansSerif = {
        package = uiFonts.sans.package;
        name = uiFonts.sans.name;
      };
      monospace = {
        package = uiFonts.monospace.package;
        name = uiFonts.monospace.name;
      };
      emoji = {
        package = uiFonts.emoji.package;
        name = uiFonts.emoji.name;
      };
      sizes = {
        applications = uiFonts.sizes.applications;
        desktop = uiFonts.sizes.desktop;
        popups = uiFonts.sizes.popups;
        terminal = uiFonts.sizes.terminal;
      };
    };
    base16Scheme = base16.dark;
    targets = lib.mkIf isThemed {
      chromium.enable = true;
      console.enable = true;
      font-packages.enable = true;
      fontconfig.enable = true;
      gtk.enable = true;
      gtksourceview.enable = true;
      qt.enable = true;
    };
  };
}
