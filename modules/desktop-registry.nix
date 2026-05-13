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
  ];
in
{
  inherit themes themedDesktops unthemedDesktops;

  desktops = themedDesktops ++ unthemedDesktops;
}
