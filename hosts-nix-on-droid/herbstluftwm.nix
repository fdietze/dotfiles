# herbstluftwm for nix-on-droid (korken), displayed on Termux:X11.
#
# Minimal first step: install hlwm + a small autostart (tags, spawn st, basic
# nav/keybinds). Launch it from a NoD shell against the Termux:X11 server:
#   DISPLAY=127.0.0.1:1 herbstluftwm        (server: termux-x11 :1 -listen tcp)
# then drive/test with `herbstclient` (e.g. `herbstclient spawn st`).
#
# The full laptop config (modules/home-manager/desktops/herbstluftwm.nix) is
# deliberately NOT reused: it is coupled to polybar, systemd user services,
# stylix theming, autorandr and laptop hardware tools — none of which apply
# under nix-on-droid's proot. Pieces get ported here incrementally.
{pkgs, ...}: {
  home.packages = [pkgs.herbstluftwm];

  home.file.".config/herbstluftwm/autostart" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      hc() { ${pkgs.herbstluftwm}/bin/herbstclient "$@"; }

      hc emit_hook reload

      # tags 1..4
      hc rename default 1 || true
      for i in 2 3 4; do hc add "$i"; done

      # keybinds (Super = Mod4; usable once the soft/hardware keyboard sends it)
      Mod=Mod4
      hc keybind $Mod-Return spawn ${pkgs.st}/bin/st
      hc keybind $Mod-q close
      hc keybind $Mod-Tab cycle
      hc keybind $Mod-space cycle_layout vertical horizontal max
      hc keybind $Mod-f fullscreen toggle
      hc keybind $Mod-Shift-r reload
      hc keybind $Mod-Shift-q quit
      for i in 1 2 3 4; do hc keybind $Mod-$i use_index $((i - 1)); done

      # appearance
      hc set frame_gap 4
      hc set window_gap 4
      hc attr theme.border_width 2
      hc attr theme.active.color '#88c0d0'
      hc attr theme.normal.color '#3b4252'

      # start a terminal so the session is not empty
      hc spawn ${pkgs.st}/bin/st
    '';
  };
}
