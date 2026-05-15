{
  desktop,
  lib,
  pkgs,
  ...
}:
lib.mkIf (desktop == "noctalia-niri") {
  # https://docs.noctalia.dev/v4/getting-started/nixos/
  programs.noctalia-shell = {
    enable = true;
    # Starter; expand once concrete preferences settle. Defaults already cover
    # bar, dock, launcher, lockscreen and wallpaper management.
    settings = { };
  };

  # Noctalia does not theme GTK/Qt apps itself and points users at nwg-look /
  # qt6ct (https://docs.noctalia.dev/v4/getting-started/faq/). Stylix is gated
  # off for this unthemed specialization, so these own app theming end-to-end.
  home.packages = with pkgs; [
    nwg-look
    qt6Packages.qt6ct
  ];

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
  };

  # Raw KDL matches the repo's existing convention of writing tool configs
  # directly (cf. polybar's config.ini in herbstluftwm.nix).
  # https://docs.noctalia.dev/v4/getting-started/compositor-settings/niri/
  xdg.configFile."niri/config.kdl".text = ''
    // Launch noctalia from the compositor. Systemd-startup is deprecated
    // upstream; spawn-at-startup is the supported entry point.
    spawn-at-startup "noctalia-shell"

    window-rule {
      geometry-corner-radius 20
      clip-to-geometry true
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
    }

    // Minimal keybinds — extend as the niri setup matures. Noctalia IPC
    // expects argument lists, not joined strings.
    binds {
      Mod+D { spawn "alacritty"; }
      Mod+Y { spawn "noctalia-shell" "ipc" "call" "launcher" "toggle"; }
      Mod+Q { close-window; }
      Mod+Shift+Q { quit; }
      XF86AudioRaiseVolume { spawn "pamixer" "--increase" "5"; }
      XF86AudioLowerVolume { spawn "pamixer" "--decrease" "5"; }
      XF86AudioMute { spawn "pamixer" "-t"; }
      XF86MonBrightnessUp { spawn "brightnessctl" "set" "+5%"; }
      XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }
    }
  '';
}
