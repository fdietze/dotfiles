{
  config,
  desktop,
  lib,
  pkgs,
  uiFonts,
  ...
}: let
  repoDir = "${config.home.homeDirectory}/projects/dotfiles";
  base16NoctaliaScheme = import ../../themes/noctalia-scheme.nix {inherit pkgs;};
in
  lib.mkIf (desktop == "noctalia-niri") {
    # https://docs.noctalia.dev/v4/getting-started/nixos/
    # Intentionally no `settings` here — the noctalia HM module would render a
    # read-only symlink at ~/.config/noctalia/settings.json, but the GUI must be
    # able to write to it. Settings are tracked via the mkOutOfStoreSymlink
    # below instead.
    programs.noctalia-shell.enable = true;

    # Noctalia does not theme GTK/Qt apps itself and points users at nwg-look /
    # qt6ct (https://docs.noctalia.dev/v4/getting-started/faq/). Stylix is gated
    # off for this unthemed specialization, so these own app theming end-to-end.
    home.packages = with pkgs; [
      nwg-look
      qt6Packages.qt6ct
      # niri ≥25.08 auto-spawns this on demand for X11 clients. Must be in PATH
      # before niri starts the user session; without it $DISPLAY stays unset and
      # X11-only apps (VirtualBox, older Electron, etc.) refuse to launch.
      xwayland-satellite
    ];

    home.sessionVariables = {
      QT_QPA_PLATFORMTHEME = "qt6ct";
    };

    # Pull alacritty's color palette from noctalia's live color scheme. Noctalia
    # renders home/noctalia/templates/alacritty.toml into this output path
    # whenever the active scheme changes (see home/noctalia/user-templates.toml).
    # The output lives under ~/.config/noctalia which is a mkOutOfStoreSymlink
    # into the repo, so the rendered file is tracked in git and exists on first
    # boot — without that, alacritty would fail to start on a missing import.
    programs.alacritty.settings.general.import = [
      "${config.home.homeDirectory}/.config/noctalia/generated/alacritty-colors.toml"
    ];

    # Kitty: live colors from noctalia. The generated file is included into
    # kitty.conf via extraConfig. Path resolves through the noctalia
    # mkOutOfStoreSymlink at ~/.config/noctalia, so the file is always present
    # (seed is tracked in git) and gets rewritten in place by noctalia's
    # template engine on every scheme change. SIGUSR1 reload is handled in
    # home/noctalia/user-templates.toml since kitty's auto_reload_config does
    # not watch include'd files.
    programs.kitty.extraConfig = ''
      include ${config.home.homeDirectory}/.config/noctalia/generated/kitty-colors.conf
    '';

    # noctalia writes its full state (settings.json, colors.json, plugins, color
    # schemes) on every GUI change. mkOutOfStoreSymlink makes ~/.config/noctalia
    # a plain symlink to the repo so noctalia can keep writing while git tracks
    # the result. The repo path must exist before activation — bootstrap done in
    # home/noctalia/.
    xdg.configFile."noctalia".source =
      config.lib.file.mkOutOfStoreSymlink "${repoDir}/home/noctalia";

    # Generate noctalia's "Base16" color scheme from modules/themes/base16.nix so
    # the same palette feeds both herbstluftwm (via stylix) and noctalia. The
    # scheme's `dark` and `light` variants come from the two halves of base16.nix
    # — noctalia's dark-mode toggle then flips between them. Installed via an
    # activation script because ~/.config/noctalia is itself a mkOutOfStoreSymlink,
    # which precludes a sibling xdg.configFile entry. Set
    # colorSchemes.predefinedScheme = "Base16" in settings.json to use it.
    home.activation.noctaliaBase16Scheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
      schemeDir="${repoDir}/home/noctalia/colorschemes/Base16"
      run mkdir -p "$schemeDir"
      run install -m 0644 ${base16NoctaliaScheme} "$schemeDir/Base16.json"
    '';

    # Raw KDL matches the repo's existing convention of writing tool configs
    # directly (cf. polybar's config.ini in herbstluftwm.nix).
    # https://docs.noctalia.dev/v4/getting-started/compositor-settings/niri/
    # Validate the generated KDL at nix-build time via `niri validate`, so a
    # syntax/schema error fails the home-manager activation instead of
    # surfacing later at runtime (e.g. via `niri msg action load-config-file`).
    xdg.configFile."niri/config.kdl".source =
      pkgs.runCommand "niri-config.kdl" {
        nativeBuildInputs = [pkgs.niri];
        passAsFile = ["configText"];
        configText = ''
          // Launch noctalia from the compositor. Systemd-startup is deprecated
          // upstream; spawn-at-startup is the supported entry point.
          spawn-at-startup "noctalia-shell"

          // Ask clients to skip drawing their own title bar / window decorations.
          // GTK/libadwaita and most Qt apps honour this; Electron typically does not.
          prefer-no-csd

          // XWayland is auto-spawned by niri ≥25.08 when xwayland-satellite is in
          // PATH — no config keyword exists. xwayland-satellite is pulled in via
          // home.packages alongside this module.

          layout {
            // gaps 0 + border (not focus-ring): border shrinks windows to fit so
            // no wallpaper shows between adjacent windows. focus-ring would draw
            // outside the window without shrinking it and overlap neighbours at
            // gaps 0. tab-indicator off for the same reason.
            //
            // knuffel decodes per-field defaults, not the struct's Default impl
            // — so any `border { ... }` block (without `off`) enables it, even
            // though Border::default() has off=true. Same trap for tab-indicator.
            gaps 0

            focus-ring {
              off
            }
            // Urgent window highlight (X11 WM_HINTS UrgencyHint equivalent on
            // Wayland: routed via xdg-activation-v1 when the compositor refuses
            // to steal focus, plus niri's set-urgent action). Colors come from
            // the noctalia include below — niri merges per-field, so an empty
            // `border { }` block is fine here as long as the include sets them.
            border { }
            tab-indicator {
              off
            }
          }

          // Pull focus-ring/border/shadow/tab-indicator colors from noctalia's
          // active MD3 palette. The file is re-rendered on every scheme/dark-mode
          // toggle (home/noctalia/templates/niri.kdl ⇢ user-templates.toml); niri
          // auto-watches included files and live-reloads on change.
          // Include must be at the top level (Configuration:-Include.md).
          include "~/.config/noctalia/generated/niri.kdl"

          // Monitor profiles. niri matches by name (connector OR EDID make+model+serial)
          // and applies the block whenever that output is connected — so this is
          // already a kanshi-style auto-applied profile.
          //
          // External 4K touch monitor: keyed by EDID so the profile follows the
          // device, not the port. Sits physically to the left of the laptop; scale
          // chosen via wdisplays.
          output "Invalid Vendor Codename - RTK MG140-UT01 demoset-1" {
            scale 2.05
            position x=0 y=0
          }
          // Built-in panel needs no block — niri auto-places it next to the
          // external when both are connected, and at 0,0 when standalone.

          workspace "1"
          workspace "2"
          workspace "3"
          workspace "4"
          workspace "5"
          workspace "6"
          workspace "7"
          workspace "8"
          workspace "9"

          window-rule {
            geometry-corner-radius 0
            clip-to-geometry true
          }

          // Main KeePassXC window only — title is "<database>.kdbx[ ...] - KeePassXC".
          // Dialogs (Unlock Database, auto-type prompts, password prompts) have
          // titles without the .kdbx token, so they fall through to the default
          // (open on focused workspace). niri has no is-dialog matcher; title
          // regex is the available proxy.
          window-rule {
            match app-id="^org\\.keepassxc\\.KeePassXC$" title="\\.kdbx.* - KeePassXC$"
            open-on-workspace "8"
          }

          window-rule {
            match app-id="^VirtualBox Manager$"
            open-on-workspace "6"
          }

          window-rule {
            match app-id="^spotify$"
            open-on-workspace "9"
          }

          debug {
            honor-xdg-activation-with-invalid-serial
          }

          // Wallpaper integration — option 1 (blurred overview backdrop).
          // Toggle "Enable overview wallpaper" ON in noctalia settings.
          layer-rule {
            match namespace="^noctalia-overview*"
            place-within-backdrop true
          }

          input {
            keyboard {
              xkb {
                layout "de,de"
                variant "neo,basic"
                options "altwin:swap_lalt_lwin"
              }
            }
            // niri's touchpad booleans are presence-flags: include the key to
            // enable, omit to disable. Tap-to-click stays disabled (no `tap` line).
            touchpad {
              natural-scroll
              dwt
              accel-speed 0.7
            }
            // Map touchscreen input to the external 4K monitor so taps land
            // on the screen the user is actually touching.
            touch {
              map-to-output "DP-2"
            }
          }

          // Adapted from the herbstluftwm bindings. niri actions are keysym-based,
          // so under the neo layout the symbols i/a/l/e land on physical h/j/k/l
          // positions just like in hlwm. Bindings that prefer feedback (volume,
          // brightness, media, lockscreen, launcher, bluetooth) go through noctalia
          // IPC so the bar's OSD reflects the change.
          binds {
            // ===== Spawn apps =====
            // terminal-here wraps $TERMINAL (kitty) with xcwd-home for cwd inheritance.
            // See modules/home-manager/launchers.nix.
            Mod+D { spawn "terminal-here"; }
            Mod+Y { spawn "noctalia-shell" "ipc" "call" "launcher" "toggle"; }
            Mod+J { spawn "sh" "-c" "$BROWSER"; }
            Mod+apostrophe { spawn "sh" "-c" "$BROWSER"; }
            Mod+B { spawn "overskride"; }
            Mod+Ctrl+B { spawn "noctalia-shell" "ipc" "call" "bluetooth" "toggle"; }

            // ===== Window =====
            Mod+Q { close-window; }
            Mod+X { close-window; }
            Mod+F { fullscreen-window; }
            Mod+H { toggle-window-floating; }
            Mod+Shift+H { switch-preset-column-width; }

            // ===== Column / stack manipulation =====
            // Mirrors hlwm's split/remove/explode bindings. Niri's column
            // model: windows live in columns side-by-side; multiple windows
            // can stack vertically inside one column.
            Mod+R     { consume-window-into-column; }   // pull next column's window into current
            Mod+comma { expel-window-from-column; }     // pop focused window out of its stack

            // ===== Focus (Arrow keys + neo i/a/l/e) =====
            Mod+Left  { focus-column-left; }
            Mod+Down  { focus-window-down; }
            Mod+Up    { focus-window-up; }
            Mod+Right { focus-column-right; }
            Mod+I { focus-column-left; }
            Mod+A { focus-window-down; }
            Mod+L { focus-window-up; }
            Mod+E { focus-column-right; }
            Mod+Tab       { focus-column-right; }
            Mod+Shift+Tab { focus-column-left; }

            // ===== Move column / window =====
            Mod+Shift+Left  { move-column-left; }
            Mod+Shift+Down  { move-window-down; }
            Mod+Shift+Up    { move-window-up; }
            Mod+Shift+Right { move-column-right; }
            Mod+Shift+I { move-column-left; }
            Mod+Shift+A { move-window-down; }
            Mod+Shift+L { move-window-up; }
            Mod+Shift+E { move-column-right; }

            // ===== Workspaces (1..9) =====
            Mod+1 { focus-workspace 1; }
            Mod+2 { focus-workspace 2; }
            Mod+3 { focus-workspace 3; }
            Mod+4 { focus-workspace 4; }
            Mod+5 { focus-workspace 5; }
            Mod+6 { focus-workspace 6; }
            Mod+7 { focus-workspace 7; }
            Mod+8 { focus-workspace 8; }
            Mod+9 { focus-workspace 9; }
            // move-column-to-workspace moves the whole column AND focuses the new
            // workspace, which matches hlwm's "chain move_index, use_index".
            Mod+Shift+1 { move-column-to-workspace 1; }
            Mod+Shift+2 { move-column-to-workspace 2; }
            Mod+Shift+3 { move-column-to-workspace 3; }
            Mod+Shift+4 { move-column-to-workspace 4; }
            Mod+Shift+5 { move-column-to-workspace 5; }
            Mod+Shift+6 { move-column-to-workspace 6; }
            Mod+Shift+7 { move-column-to-workspace 7; }
            Mod+Shift+8 { move-column-to-workspace 8; }
            Mod+Shift+9 { move-column-to-workspace 9; }
            // Move column to workspace N without following — mirrors hlwm's
            // Mod4-Shift-Ctrl-<digit> (move_index without use_index).
            Mod+Shift+Ctrl+1 { move-column-to-workspace 1 focus=false; }
            Mod+Shift+Ctrl+2 { move-column-to-workspace 2 focus=false; }
            Mod+Shift+Ctrl+3 { move-column-to-workspace 3 focus=false; }
            Mod+Shift+Ctrl+4 { move-column-to-workspace 4 focus=false; }
            Mod+Shift+Ctrl+5 { move-column-to-workspace 5 focus=false; }
            Mod+Shift+Ctrl+6 { move-column-to-workspace 6 focus=false; }
            Mod+Shift+Ctrl+7 { move-column-to-workspace 7 focus=false; }
            Mod+Shift+Ctrl+8 { move-column-to-workspace 8 focus=false; }
            Mod+Shift+Ctrl+9 { move-column-to-workspace 9 focus=false; }

            // Cycle through workspaces (hlwm c/v).
            Mod+C            { focus-workspace-down; }
            Mod+Shift+C      { move-column-to-workspace-down; }
            Mod+Shift+Ctrl+C { move-column-to-workspace-down focus=false; }
            Mod+V            { focus-workspace-up; }
            Mod+Shift+V      { move-column-to-workspace-up; }
            Mod+Shift+Ctrl+V { move-column-to-workspace-up focus=false; }

            // Toggle back to the previously focused workspace (hlwm Mod4-w).
            Mod+W { focus-workspace-previous; }

            // ===== Resize (hlwm Shift+g/r/n/t) =====
            Mod+Shift+N { set-column-width "-10%"; }
            Mod+Shift+T { set-column-width "+10%"; }
            Mod+Shift+G { set-window-height "-10%"; }
            Mod+Shift+R { set-window-height "+10%"; }

            // ===== Monitors =====
            Mod+O { focus-monitor-right; }
            Mod+U { focus-monitor-left; }
            Mod+Shift+O { move-column-to-monitor-right; }
            Mod+Shift+U { move-column-to-monitor-left; }

            // ===== System =====
            Mod+Shift+Y      { spawn "niri" "msg" "action" "load-config-file"; }
            Mod+Shift+X      { quit; }
            Mod+Ctrl+Shift+Q { spawn "systemctl" "poweroff"; }
            Mod+Ctrl+Shift+X { spawn "systemctl" "poweroff"; }
            Mod+Ctrl+Shift+Y { spawn "systemctl" "reboot"; }
            Mod+Escape       { spawn "noctalia-shell" "ipc" "call" "lockScreen" "lock"; }

            // ===== Theme — mirrors herbstluftwm's Mod+Ctrl+k/s. Noctalia handles
            // automatic dark/light switching on its own; these just force it.
            Mod+Ctrl+K { spawn "noctalia-shell" "ipc" "call" "darkMode" "setLight"; }
            Mod+Ctrl+S { spawn "noctalia-shell" "ipc" "call" "darkMode" "setDark"; }

            // ===== Audio — noctalia IPC drives the OSD =====
            XF86AudioRaiseVolume { spawn "noctalia-shell" "ipc" "call" "volume" "increase"; }
            XF86AudioLowerVolume { spawn "noctalia-shell" "ipc" "call" "volume" "decrease"; }
            XF86AudioMute        { spawn "noctalia-shell" "ipc" "call" "volume" "muteOutput"; }
            Mod+Ctrl+H { spawn "noctalia-shell" "ipc" "call" "volume" "increase"; }
            Mod+Ctrl+N { spawn "noctalia-shell" "ipc" "call" "volume" "decrease"; }
            Mod+Ctrl+M { spawn "noctalia-shell" "ipc" "call" "volume" "muteOutput"; }

            // ===== Brightness =====
            XF86MonBrightnessUp   { spawn "noctalia-shell" "ipc" "call" "brightness" "increase"; }
            XF86MonBrightnessDown { spawn "noctalia-shell" "ipc" "call" "brightness" "decrease"; }
            Mod+Ctrl+G { spawn "noctalia-shell" "ipc" "call" "brightness" "increase"; }
            Mod+Ctrl+R { spawn "noctalia-shell" "ipc" "call" "brightness" "decrease"; }
            // Fine adjust (1%) — noctalia IPC has no step argument, so go direct.
            // Absolute path because niri's spawn doesn't see user PATH additions.
            Mod+Ctrl+Shift+G { spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "+1%"; }
            Mod+Ctrl+Shift+R { spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "1%-"; }

            // ===== Bluetooth =====
            XF86Bluetooth { spawn "noctalia-shell" "ipc" "call" "bluetooth" "toggle"; }

            // ===== Media (neo ü/ö/ä/p/z) =====
            Mod+udiaeresis { spawn "noctalia-shell" "ipc" "call" "media" "previous"; }
            Mod+odiaeresis { spawn "noctalia-shell" "ipc" "call" "media" "play"; }
            Mod+adiaeresis { spawn "noctalia-shell" "ipc" "call" "media" "playPause"; }
            Mod+P { spawn "noctalia-shell" "ipc" "call" "media" "stop"; }
            Mod+Z { spawn "noctalia-shell" "ipc" "call" "media" "next"; }

            // ===== Timewarrior =====
            Mod+Shift+odiaeresis { spawn "timew" "continue"; }
            Mod+Shift+P          { spawn "timew" "stop"; }

            // ===== Screenshots — niri ships a region selector that copies to clipboard =====
            Print          { screenshot-screen; }
            Ctrl+Mod+Print { screenshot; }
          }
        '';
      } ''
        cp "$configTextPath" "$out"
        # niri validate follows `include` directives. The included noctalia.kdl
        # lives under $HOME at runtime but $HOME is /homeless-shelter inside the
        # nix sandbox, so the include target wouldn't exist during validation.
        # Stage the seed file at the expected tilde-expanded path before running
        # the validator — only affects validation, runtime resolves to the real
        # $HOME and lets noctalia overwrite it on every theme change.
        export HOME="$TMPDIR/home"
        install -Dm0644 ${../../../home/noctalia/generated/niri.kdl} \
          "$HOME/.config/noctalia/generated/niri.kdl"
        niri validate -c "$out"
      '';
  }
