{
  lib,
  pkgs,
  desktop,
  theme,
  ...
}:
let
  desktopRegistry = import ../desktop-registry.nix;
  hasThemeVariants = builtins.elem desktop desktopRegistry.themedDesktops;
  currentThemeTarget = "theme-${theme}.target";
  wallpaperTarget = mode: if mode == "light" then "desktop-light" else "desktop";
  mkWallpaperScript =
    mode:
    pkgs.writeShellScript "apply-wallpaper-${mode}" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      set_wallpaper() {
        local path="$1"
        local uri="file://''${path}"

        ${pkgs.coreutils}/bin/ln -sfn "''${path}" "$HOME/frottage/current-wallpaper.jpg"

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

      TARGET=${wallpaperTarget mode}

      current_hour_utc="$(${pkgs.coreutils}/bin/date -u +%H)"
      current_date_utc="$(${pkgs.coreutils}/bin/date -u +%F)"

      if ((10#$current_hour_utc < 1)); then
        slot_date="$(${pkgs.coreutils}/bin/date -u -d 'yesterday' +%F)"
        slot_hour="19"
      elif ((10#$current_hour_utc < 7)); then
        slot_date="$current_date_utc"
        slot_hour="01"
      elif ((10#$current_hour_utc < 13)); then
        slot_date="$current_date_utc"
        slot_hour="07"
      elif ((10#$current_hour_utc < 19)); then
        slot_date="$current_date_utc"
        slot_hour="13"
      else
        slot_date="$current_date_utc"
        slot_hour="19"
      fi

      TIMESTAMP_KEY="''${slot_date}_''${slot_hour}-00-00"
      WALLPAPER_FILENAME="wallpaper-''${TARGET}-''${TIMESTAMP_KEY}.jpg"

      ${pkgs.coreutils}/bin/mkdir -p "$HOME/frottage"

      DOWNLOAD_URL="https://frottage.app/static/''${WALLPAPER_FILENAME}"
      OUTPUT_PATH="$HOME/frottage/''${WALLPAPER_FILENAME}"
      if [[ -e "$OUTPUT_PATH" ]]; then
        echo "Using cached wallpaper for slot: ''${TIMESTAMP_KEY}"
        set_wallpaper "$OUTPUT_PATH"
        exit 0
      fi

      echo "Starting wallpaper download for theme: ''${TARGET}, slot: ''${TIMESTAMP_KEY}"
      echo "Downloading $DOWNLOAD_URL to $OUTPUT_PATH with retries"

      if ${pkgs.curl}/bin/curl --retry 5 --retry-delay 10 --retry-all-errors -sfSL -o "$OUTPUT_PATH" "$DOWNLOAD_URL"; then
        echo "Download successful."
        set_wallpaper "$OUTPUT_PATH"
        exit 0
      else
        curl_exit_code=$?
        echo "curl command failed after retries with exit code: $curl_exit_code." >&2
        echo "Failed to download wallpaper from $DOWNLOAD_URL." >&2
        echo "Falling back to the most recent cached wallpaper." >&2
        latest_cached="$(${pkgs.findutils}/bin/find "$HOME/frottage" -maxdepth 1 -type f -name 'wallpaper-*.jpg' -printf '%T@ %p\n' | ${pkgs.coreutils}/bin/sort -nr | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gawk}/bin/awk '{print $2}')"
        if [[ -n "''${latest_cached:-}" && -e "''${latest_cached}" ]]; then
          set_wallpaper "$latest_cached" || true
        fi
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
      PartOf = [ currentThemeTarget ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${mkWallpaperScript theme}";
    };
    Install.WantedBy = [ currentThemeTarget ];
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
      WantedBy = [ "timers.target" ];
    };
  };
}
