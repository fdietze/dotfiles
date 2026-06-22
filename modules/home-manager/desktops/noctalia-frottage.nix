# Frottage daily AI wallpaper for the noctalia-niri desktop.
#
# Ports modules/home-manager/wallpaper.nix (X11/feh + GNOME/gsettings) to
# noctalia v5: same 4x/day download schedule and shared download helper, but the
# wallpaper is applied through noctalia's IPC (`noctalia msg wallpaper-set`) and
# the dark/light frottage variant tracks noctalia's runtime mode.
#
# Why a unique dated path each slot (not a stable symlink): noctalia skips the
# image when the new path equals the current one (wallpaper.cpp applyWallpaperChange)
# and its texture cache keys by path, so only a changing path refreshes the image.
# That path is persisted into the git-tracked settings.toml — the resulting churn
# is absorbed by the noctalia-wallpaper git clean filter (see .gitattributes).
{
  config,
  desktop,
  lib,
  pkgs,
  ...
}: let
  # Slot calc + download-with-retry + cache fallback + current-wallpaper.jpg
  # symlink, shared with wallpaper.nix.
  frottageDownload = import ../frottage-download.nix {inherit pkgs;};
  noctalia = "${config.programs.noctalia.package}/bin/noctalia";

  # Applies the frottage wallpaper variant for a mode. Invoked two ways:
  #   - by the systemd timer with no argument -> resolves the mode via IPC;
  #   - by the noctalia frottage-trigger post_hook with {{mode}} as $1, so the
  #     variant swaps on every dark/light toggle and at the startup render.
  frottageNoctalia = pkgs.writeShellScript "frottage-noctalia" ''
    set -euo pipefail
    mode="''${1:-$(${noctalia} msg theme-mode-get)}"
    case "$mode" in
      light) target=desktop-light ;;
      *) target=desktop ;;
    esac
    if path="$(${frottageDownload} "$target")"; then
      ${noctalia} msg wallpaper-set "$path"
    else
      echo "frottage-noctalia: no wallpaper available" >&2
      exit 1
    fi
  '';
in
  lib.mkIf (desktop == "noctalia-niri") {
    # Stable path so the template post_hook reference survives rebuilds (mirrors
    # noctalia-gtk-theme). On PATH via $HOME/bin.
    home.file."bin/frottage-noctalia" = {
      executable = true;
      source = frottageNoctalia;
    };

    # Re-apply the correct frottage variant on every dark/light toggle and at the
    # startup render. Merges into the templates.user set defined in
    # noctalia-niri.nix (nix merges attrsets across modules). The template source
    # is picked up by that module's noctalia/templates out-of-store symlink.
    programs.noctalia.settings.theme.templates.user."frottage-trigger" = {
      input_path = "templates/frottage-trigger.txt";
      output_path = "${config.home.homeDirectory}/.config/noctalia/generated/frottage-trigger.txt";
      post_hook = "${config.home.homeDirectory}/bin/frottage-noctalia {{mode}}";
    };

    # Fetch a fresh wallpaper at each 6-hourly slot. The post_hook only covers
    # mode toggles + startup; this covers new daily art without a toggle. Same
    # schedule and unit name as wallpaper.nix's frottage (mutually exclusive via
    # the desktop gate, so the shared name never collides).
    systemd.user.services.frottage = {
      Unit = {
        Description = "Frottage wallpaper (noctalia)";
        After = [
          "graphical-session.target"
          "network-online.target"
          "nss-lookup.target"
        ];
        Wants = [
          "network-online.target"
          "nss-lookup.target"
        ];
        # Ties the service to the graphical session so it inherits WAYLAND_DISPLAY
        # (required to reach the noctalia IPC socket).
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${frottageNoctalia}";
      };
    };

    systemd.user.timers.frottage = {
      Unit.Description = "Frottage wallpaper timer (noctalia)";
      Timer = {
        OnActiveSec = "15s";
        OnCalendar = "*-*-* 01,07,13,19:00:00 UTC";
        Persistent = true; # Catch slots missed during suspend/shutdown.
      };
      Install.WantedBy = ["timers.target"];
    };
  }
