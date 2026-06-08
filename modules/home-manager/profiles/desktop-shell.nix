# GUI-Session-Shell-Sugar: Shell-Aliase, die einen Desktop/GUI-Kontext
# voraussetzen und/oder Desktop-Pakete referenzieren. Bewusst NICHT im headless
# shell-core, damit standalone- und Template-Profile schlank bleiben (kein
# zbar/espeak/firefox im Closure). Wird nur von shared.nix importiert; gurke
# merged diese Aliase mit denen aus shell-core.
{pkgs, ...}: {
  home.shellAliases = {
    qrscan = "LD_PRELOAD=/usr/lib/libv4l/v4l1compat.so ${pkgs.zbar}/bin/zbarcam --raw /dev/video0";
    tclip = ''tmate display -p "#{tmate_ssh}" | xclip -selection clipboard''; # tmate session token to clipboard
    feh = "feh --auto-zoom --scale-down";
    signal-desktop = ''sec && signal-desktop --password-store="gnome-libsecret"'';
    # No --force-device-scale-factor: Chromium derives its device scale from the
    # session itself — Xft.dpi 192 on X11 (herbstluftwm) and the per-output
    # scale 2.0 on Wayland (niri). The old flag stacked multiplicatively on the
    # Wayland compositor scale, over-zooming the UI.
    chromium-no-plugins = "chromium --disable-extensions --disable-plugins";
    online-wait = "until online; do; sleep 3; done; ${pkgs.espeak}/bin/espeak -p 30 'online'; ${pkgs.espeak}/bin/espeak -p 80 'online'; ${pkgs.espeak}/bin/espeak -p 50 'online'";
  };
}
