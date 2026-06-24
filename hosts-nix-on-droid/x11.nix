# Minimal X11 client side for nix-on-droid (korken).
#
# nix-on-droid can't host an X server itself (the Termux:X11 launcher needs
# Android's app_process plumbing), so the server stays in *regular Termux* and
# we connect over loopback TCP. See nix-community/nix-on-droid#305 (Resonious'
# `-listen tcp` approach).
#
#   Termux (X server):     termux-x11 :1 -listen tcp
#   nix-on-droid (client): DISPLAY=127.0.0.1:1, then run any nixpkgs X client
#
# Smoke-test stage: a single terminal to prove the pipe before adding a window
# manager.
#
# Terminal choice: st, NOT xterm. xterm's spawn() unconditionally calls
# setuid(getuid()) to drop privileges, which returns ENOSYS under nix-on-droid's
# proot ("spawn: setuid() failed") — no flag avoids it, so xterm can never spawn
# a shell here. st (and alacritty/kitty) don't setuid, so they work.
{pkgs, ...}: let
  # nix-on-droid is not NixOS: there is no /etc/fonts/fonts.conf, and HM's
  # fonts.fontconfig only drops conf.d snippets without a usable base config, so
  # Xft clients (st, GTK/Qt) die with "Cannot load default config file".
  # makeFontsConf gives a self-contained fonts.conf that includes our fonts;
  # FONTCONFIG_FILE points every Xft client at it.
  fontsConf = pkgs.makeFontsConf {fontDirectories = [pkgs.dejavu_fonts];};
in {
  home.packages = [
    pkgs.st
    # X setup/diagnostics: xrandr (monitor geometry on the external display),
    # setxkbmap/xmodmap/xev/xinput (verify how Termux:X11 maps a real BT
    # keyboard — layout + which physical modifier reaches Mod4).
    pkgs.xorg.xrandr
    pkgs.xorg.setxkbmap
    pkgs.xorg.xmodmap
    pkgs.xorg.xev
    pkgs.xorg.xinput
    pkgs.xorg.xdpyinfo
  ];

  home.sessionVariables = {
    # The Termux:X11 server started with `-listen tcp` exposes display :1 on
    # loopback; nixpkgs X clients connect there.
    DISPLAY = "127.0.0.1:1";
    FONTCONFIG_FILE = fontsConf;
  };
}
