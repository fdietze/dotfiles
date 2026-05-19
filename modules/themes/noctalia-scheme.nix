{pkgs}: let
  base16 = import ./base16.nix;
  withHash = c: "#${c}";

  # Map one base16 variant to noctalia's MD3 + ANSI shape.
  # `onAccent` is the contrast color used on top of primary/secondary/etc.
  # For dark schemes that's the background; for light it's near-white.
  variant = palette: onAccent: {
    mPrimary = withHash palette.base0B; # green accent (matches herbstluftwm)
    mOnPrimary = withHash onAccent;
    mSecondary = withHash palette.base0E; # magenta
    mOnSecondary = withHash onAccent;
    mTertiary = withHash palette.base0D; # blue
    mOnTertiary = withHash onAccent;
    mError = withHash palette.base08; # red
    mOnError = withHash onAccent;
    mSurface = withHash palette.base00;
    mOnSurface = withHash palette.base05;
    mSurfaceVariant = withHash palette.base01;
    mOnSurfaceVariant = withHash palette.base04;
    mOutline = withHash palette.base02;
    mShadow = withHash palette.base00;
    mHover = withHash palette.base0B;
    mOnHover = withHash onAccent;
    terminal = {
      normal = {
        black = withHash palette.base00;
        red = withHash palette.base08;
        green = withHash palette.base0B;
        yellow = withHash palette.base09; # orange slot
        blue = withHash palette.base0D;
        magenta = withHash palette.base0E;
        cyan = withHash palette.base0C;
        white = withHash palette.base05;
      };
      bright = {
        black = withHash palette.base03;
        red = withHash palette.base08;
        green = withHash palette.base0B;
        yellow = withHash palette.base0A;
        blue = withHash palette.base0D;
        magenta = withHash palette.base0E;
        cyan = withHash palette.base0C;
        white = withHash palette.base07;
      };
      foreground = withHash palette.base05;
      background = withHash palette.base00;
      selectionFg = withHash palette.base05;
      selectionBg = withHash palette.base02;
      cursorText = withHash palette.base00;
      cursor = withHash palette.base05;
    };
  };

  # onAccent is the contrast color drawn on top of mPrimary/mSecondary/etc.
  # Dark schemes pair a pastel primary with a dark on-color (use bg, base00).
  # Light schemes pair a saturated primary with a light on-color — also base00
  # here, because in this light palette base00 is white (base07 is reused as
  # black fg, so it's NOT a safe choice for an on-accent slot).
  scheme = {
    dark = variant base16.dark base16.dark.base00;
    light = variant base16.light base16.light.base00;
  };
in
  pkgs.writeText "Stylix.json" (builtins.toJSON scheme)
