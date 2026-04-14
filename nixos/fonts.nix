{pkgs}: {
  dpi = 210;

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

  sizes = {
    applications = 12;
    desktop = 12;
    popups = 30;
    terminal = 17;
  };
}
