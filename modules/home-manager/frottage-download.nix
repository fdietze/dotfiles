# Shared frottage downloader used by every desktop's wallpaper integration
# (X11/feh + GNOME/gsettings via wallpaper.nix, Wayland/noctalia via
# desktops/noctalia-frottage.nix). Encapsulates the one piece of frottage
# knowledge: the per-slot URL scheme, the download-with-retry + fallback-to-cache
# logic, and the stable `current-wallpaper.jpg` symlink. Backends stay in the
# callers.
#
# Contract: `frottage-download <TARGET>` where TARGET is `desktop` (dark) or
# `desktop-light`. Ensures the current slot's wallpaper is cached (downloading if
# needed, else falling back to the newest cached file), refreshes the
# `current-wallpaper.jpg` symlink, prints the absolute path to stdout (all logs go
# to stderr) and exits 0; exits 1 only when no wallpaper is available at all.
{pkgs}:
pkgs.writeShellScript "frottage-download" ''
  #!${pkgs.bash}/bin/bash
  set -euo pipefail

  TARGET="''${1:?usage: frottage-download <desktop|desktop-light>}"

  CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/frottage"
  ${pkgs.coreutils}/bin/mkdir -p "$CACHE_DIR"

  # Frottage publishes a new wallpaper every 6 hours at 01/07/13/19 UTC. Pick the
  # slot the current UTC hour falls into; before 01:00 UTC use yesterday's 19:00.
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
  OUTPUT_PATH="$CACHE_DIR/''${WALLPAPER_FILENAME}"
  DOWNLOAD_URL="https://frottage.app/static/''${WALLPAPER_FILENAME}"

  # Refresh the stable symlink and print the chosen path. Both desktop backends
  # and the noctalia clean-filter placeholder reference current-wallpaper.jpg.
  emit() {
    ${pkgs.coreutils}/bin/ln -sfn "$1" "$CACHE_DIR/current-wallpaper.jpg"
    printf '%s\n' "$1"
  }

  if [[ -e "$OUTPUT_PATH" ]]; then
    echo "Using cached wallpaper for slot: ''${TIMESTAMP_KEY}" >&2
    emit "$OUTPUT_PATH"
    exit 0
  fi

  echo "Downloading $DOWNLOAD_URL to $OUTPUT_PATH with retries" >&2
  if ${pkgs.curl}/bin/curl --retry 5 --retry-delay 10 --retry-all-errors -sfSL -o "$OUTPUT_PATH" "$DOWNLOAD_URL"; then
    echo "Download successful." >&2
    emit "$OUTPUT_PATH"
    exit 0
  fi

  echo "Download failed after retries; falling back to newest cached wallpaper." >&2
  latest_cached="$(${pkgs.findutils}/bin/find "$CACHE_DIR" -maxdepth 1 -type f -name 'wallpaper-*.jpg' -printf '%T@ %p\n' | ${pkgs.coreutils}/bin/sort -nr | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.gawk}/bin/awk '{print $2}')"
  if [[ -n "''${latest_cached:-}" && -e "''${latest_cached}" ]]; then
    emit "$latest_cached"
    exit 0
  fi

  echo "No wallpaper available (download failed and cache empty)." >&2
  exit 1
''
