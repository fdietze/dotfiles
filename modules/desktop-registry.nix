let
  themes = [
    "dark"
    "light"
  ];
  themedDesktops = [
    "gnome"
    "herbstluftwm"
  ];
  unthemedDesktops = [
    "noctalia-niri"
  ];
in {
  inherit themes themedDesktops unthemedDesktops;

  desktops = themedDesktops ++ unthemedDesktops;
}
