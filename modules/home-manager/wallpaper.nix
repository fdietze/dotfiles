{
  lib,
  pkgs,
  desktop,
  theme,
  ...
}: let
  desktopRegistry = import ../desktop-registry.nix;
  hasThemeVariants = builtins.elem desktop desktopRegistry.themedDesktops;
  currentThemeTarget = "theme-${theme}.target";
  # Shared slot/download/fallback logic + current-wallpaper.jpg symlink. This
  # module supplies only the X11 (feh) / GNOME (gsettings) backend below.
  frottageDownload = import ./frottage-download.nix {inherit pkgs;};
  wallpaperTarget = mode:
    if mode == "light"
    then "desktop-light"
    else "desktop";
  mkWallpaperScript = mode:
    pkgs.writeShellScript "apply-wallpaper-${mode}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      set_wallpaper() {
        local path="$1"
        local uri="file://''${path}"

        if [[ "''${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] || [[ "''${DESKTOP_SESSION:-}" == gnome ]]; then
          echo "Setting wallpaper using GNOME gsettings."
          ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-options 'zoom'
          ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri "''${uri}"
          ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri-dark "''${uri}"
        elif [[ -n "''${DISPLAY:-}" ]]; then
          echo "Setting wallpaper using feh."
          ${pkgs.feh}/bin/feh --bg-fill "''${path}"
        else
          echo "No supported wallpaper backend found for the current session." >&2
        fi
      }

      # Download/cache/fallback + current-wallpaper.jpg symlink is shared; this
      # script only applies the resolved path via the X11/GNOME backend.
      if path="$(${frottageDownload} ${wallpaperTarget mode})"; then
        set_wallpaper "$path"
      else
        echo "frottage-download produced no wallpaper." >&2
        exit 1
      fi
    '';
in
  lib.mkIf hasThemeVariants {
    systemd.user.services.frottage = {
      Unit = {
        Description = "Frottage";
        After = [
          "graphical-session-pre.target"
          "network-online.target"
          "nss-lookup.target"
        ]; # Ensure graphical session and network are available
        Wants = [
          "network-online.target"
          "nss-lookup.target"
        ]; # Require network connection
        PartOf = [
          "graphical-session.target"
        ]; # Tie service lifetime to graphical session
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${mkWallpaperScript theme}";
      };
    };

    systemd.user.services."wallpaper-${theme}" = {
      Unit = {
        Description = "Apply ${theme} wallpaper";
        After = [
          "graphical-session.target"
          "network-online.target"
          "nss-lookup.target"
        ];
        Wants = [
          "network-online.target"
          "nss-lookup.target"
        ];
        PartOf = [currentThemeTarget];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${mkWallpaperScript theme}";
      };
      Install.WantedBy = [currentThemeTarget];
    };

    systemd.user.timers.frottage = {
      Unit = {
        Description = "Frottage Timer";
      };
      Timer = {
        OnActiveSec = "15s";
        OnCalendar = "*-*-* 01,07,13,19:00:00 UTC";
        Persistent = true; # Run job if missed due to suspend/shutdown
      };
      Install = {
        WantedBy = ["timers.target"];
      };
    };
  }
