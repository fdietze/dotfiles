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

  sizes = {
    applications = 12;
    desktop = 13;
    popups = 14;
    statusbar = 11;
    terminal = 17;
  };
}
