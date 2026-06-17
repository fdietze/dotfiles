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
  home.packages = [pkgs.xterm];

  # The Termux:X11 server started with `-listen tcp` exposes display :1 on
  # loopback; nixpkgs X clients connect there.
  home.sessionVariables.DISPLAY = "127.0.0.1:1";
}
