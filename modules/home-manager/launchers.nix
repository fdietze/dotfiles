# Cross-desktop application defaults. Centralizes the "what is my terminal /
# browser / editor" choice so WM keybindings and shell env stay in sync. WM
# binding files (herbstluftwm, noctalia-niri, gnome) reference the wrapper
# scripts and env vars from here.
{pkgs, ...}: let
  terminalPkg = pkgs.kitty;
  terminalBin = "${terminalPkg}/bin/kitty";

  # Same xcwd-home derivation as packages.nix; nix dedupes by output hash so
  # this does not add to closure size. Kept local so terminal-here is hermetic
  # (does not depend on PATH ordering during WM spawn).
  xcwdHome = pkgs.callPackage ./bin/xcwd-home/package.nix {};

  terminalHere = pkgs.writeShellApplication {
    name = "terminal-here";
    runtimeInputs = [terminalPkg xcwdHome];
    # xcwd-home detects the focused window's cwd under niri (NIRI_SOCKET) or
    # X11 (xdotool) and falls back to $HOME otherwise (e.g. GNOME native-
    # Wayland windows without XWayland). The terminal binary's cwd flag is
    # hardcoded here because there is no standard across terminals
    # (kitty: -d, alacritty: --working-directory, wezterm: start --cwd).
    text = ''
      exec ${terminalBin} -d "$(xcwd-home)" "$@"
    '';
  };
in {
  home.packages = [terminalHere];

  home.sessionVariables = {
    # Used by shells, $TERMINAL-aware tools, and scripts. WM keybindings
    # invoke `terminal-here` directly when they want a cwd-aware spawn.
    TERMINAL = terminalBin;
    # BROWSER lebt hier (statt im headless shell-core), weil es firefox ins
    # Closure zieht und nur im Desktop-Kontext sinnvoll ist.
    BROWSER = "${pkgs.firefox}/bin/firefox";
    MOZ_USE_XINPUT2 = 1; # fix firefox scrolling, enable touchpad gestures
  };
}
