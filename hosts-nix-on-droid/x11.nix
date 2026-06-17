# Minimal X11 client side for nix-on-droid (korken).
#
# nix-on-droid can't host an X server itself (the Termux:X11 launcher needs
# Android's app_process plumbing), so the server stays in *regular Termux* and
# we connect over loopback TCP. See nix-community/nix-on-droid#305 (Resonious'
# `-listen tcp` approach).
#
#   Termux (X server):    termux-x11 :1 -listen tcp
#   nix-on-droid (client): DISPLAY=127.0.0.1:1, then run any nixpkgs X client
#
# Smoke-test stage: a single client (xterm) to prove the pipe before adding a
# window manager.
{pkgs, ...}: let
  # nix-on-droid is not NixOS: there is no /etc/fonts/fonts.conf, and HM's
  # fonts.fontconfig only drops conf.d snippets without a usable base config, so
  # Xft clients (xterm -fa, GTK/Qt) die with "Cannot load default config file".
  # makeFontsConf gives a self-contained fonts.conf that includes our fonts;
  # FONTCONFIG_FILE points every Xft client at it.
  fontsConf = pkgs.makeFontsConf {fontDirectories = [pkgs.dejavu_fonts];};
in {
  home.packages = [pkgs.xterm];

  home.sessionVariables = {
    # The Termux:X11 server started with `-listen tcp` exposes display :1 on
    # loopback; nixpkgs X clients connect there.
    DISPLAY = "127.0.0.1:1";
    FONTCONFIG_FILE = fontsConf;
  };

  # The Termux:X11 server serves no core X fonts, so a bare `xterm` (which wants
  # the core "fixed" font) exits immediately. Default it to a fontconfig/Xft
  # face. termux-x11 sets no RESOURCE_MANAGER, so xterm reads ~/.Xdefaults
  # directly — no xrdb/session manager needed.
  home.file.".Xdefaults".text = ''
    XTerm.vt100.faceName: DejaVu Sans Mono
    XTerm.vt100.faceSize: 12
  '';
}
