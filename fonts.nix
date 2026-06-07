{pkgs}: {
  serif = {
    package = pkgs.noto-fonts;
    name = "Noto Serif";
  };

  sans = {
    package = pkgs.noto-fonts;
    name = "Noto Sans";
  };

  monospace = {
    package = pkgs.nerd-fonts.noto;
    name = "NotoSansM Nerd Font Mono";
  };

  emoji = {
    package = pkgs.noto-fonts-color-emoji;
    name = "Noto Color Emoji";
  };

  icons = {
    package = pkgs.material-design-icons;
    name = "Material Design Icons";
  };

  # Single source of truth for the HiDPI scale across X11 and Wayland.
  # 192 = 2 × 96 (integer 2× scaling). Consumers:
  #   - herbstluftwm: Xft.dpi (lightdm session-wrapper merges ~/.Xresources)
  #   - noctalia-niri: per-output `scale 2.0` (= 192/96) for eDP-1
  #   - polybar: dpi-x / dpi-y (polybar's own DPI; does NOT read Xft.dpi)
  # Toolkits that honour Xft.dpi (GTK/Pango, Qt, winit, Chromium on X11) follow
  # automatically; native-Wayland apps follow the compositor scale.
  dpi = 192;

  sizes = {
    applications = 9;
    desktop = 9;
    popups = 9;
    statusbar = 9;
    terminal = 9;
  };
}
