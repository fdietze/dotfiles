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
{pkgs, ...}: {
  home.packages = [
    pkgs.xterm
    pkgs.dejavu_fonts # scalable mono/sans for fontconfig (Xft) clients
  ];

  # A minimal nix-on-droid has no fontconfig, so Xft clients fail with
  # "Cannot load default config file". Enable it and provide a font.
  fonts.fontconfig.enable = true;

  # The Termux:X11 server serves no core X fonts, so a bare `xterm` (which wants
  # the core "fixed" font) exits immediately. Default it to a fontconfig/Xft
  # face. termux-x11 sets no RESOURCE_MANAGER, so xterm reads ~/.Xdefaults
  # directly — no xrdb/session manager needed.
  home.file.".Xdefaults".text = ''
    XTerm.vt100.faceName: DejaVu Sans Mono
    XTerm.vt100.faceSize: 12
  '';

  # The Termux:X11 server started with `-listen tcp` exposes display :1 on
  # loopback; nixpkgs X clients connect there.
  home.sessionVariables.DISPLAY = "127.0.0.1:1";
}
