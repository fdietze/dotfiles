#!/usr/bin/env bash
# setup-new-host.sh — Bootstrap dieses NixOS/Home-Manager-Setups auf einer
# laufenden NixOS-Maschine. Gedacht für:
#   bash <(curl -fsSL https://raw.githubusercontent.com/fdietze/dotfiles/master/scripts/setup-new-host.sh)
# Process Substitution (bash <(...)) hält stdin am Terminal, damit die
# interaktiven Abfragen unten funktionieren, und vermeidet das Ausführen eines
# halb heruntergeladenen Scripts. Das Script editiert kein Nix und ist sudo-frei
# bis zum optionalen Rebuild.
set -euo pipefail

REPO_URL="https://github.com/fdietze/dotfiles.git"
RAW_URL="https://raw.githubusercontent.com/fdietze/dotfiles/master/scripts/setup-new-host.sh"
REPO_DIR="$HOME/projects/dotfiles"

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# 1. git sicherstellen (auf minimalem NixOS evtl. nicht installiert). Unter
#    nix-shell neu starten, dann ist git im PATH.
if ! command -v git >/dev/null 2>&1; then
  say "git nicht gefunden — starte unter nix-shell -p git neu."
  exec nix-shell -p git --run "bash <(curl -fsSL $RAW_URL)"
fi

# 2. Repo klonen (falls noch nicht vorhanden).
if [ -d "$REPO_DIR/.git" ]; then
  say "Repo existiert bereits: $REPO_DIR"
else
  say "Klone Repo nach $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
fi

# Aktuelles System (z. B. x86_64-linux / aarch64-linux).
ARCH="$(nix eval --raw --impure --expr builtins.currentSystem)"
say "Architektur: $ARCH"

# 3. Modus wählen (Abfrage explizit von /dev/tty, da stdin bei `curl | bash`
#    belegt sein kann).
printf '\nWas einrichten?\n  [1] NixOS + Home Manager (ganzes System)\n  [2] Nur Home Manager (Shell-Profil)\n  [3] Nix-on-Droid (korken)\n'
read -r -p "Auswahl [1/2/3]: " MODE </dev/tty

if [ "$MODE" = "2" ]; then
  # 4. Nur Home Manager: Shell-Profil aus dem geklonten Repo aktivieren.
  say "Home-Manager-Shell-Profil aktivieren: felix@$ARCH"
  nix run home-manager -- switch -b backup --flake "$REPO_DIR#felix@$ARCH"
  say "Fertig. Neue Shell starten (z. B. 'exec zsh')."
  exit 0
fi

if [ "$MODE" = "3" ]; then
  # 5. Nix-on-Droid: Der Laufzeit-Hostname bleibt dort immer "localhost";
  #    die stabile Geräte-ID ist deshalb der Flake-Output "korken".
  if ! command -v nix-on-droid >/dev/null 2>&1; then
    say "nix-on-droid nicht gefunden — Modus 3 muss in der initialisierten Nix-on-Droid-App laufen."
    exit 1
  fi

  say "Nix-on-Droid-Konfiguration aktivieren: korken"
  nix-on-droid switch --flake "$REPO_DIR#korken"
  say "Fertig. Neue Shell starten (z. B. 'exec zsh')."
  exit 0
fi

# 6. NixOS + Home Manager.
HOST="$(hostname)"
say "Hostname: $HOST"

if [ -d "$REPO_DIR/hosts-nixos/$HOST" ]; then
  say "Host '$HOST' ist bereits definiert — kein Template nötig."
else
  say "Neuer Host '$HOST' — erzeuge aus Template."
  cp -r "$REPO_DIR/hosts-nixos/template" "$REPO_DIR/hosts-nixos/$HOST"
  rm -f "$REPO_DIR/hosts-nixos/$HOST/.gitkeep-hardware"
  printf '%s\n' "$ARCH" >"$REPO_DIR/hosts-nixos/$HOST/system"
  # --show-hardware-config druckt die erkannte Hardware (Filesystems, Swap,
  # Boot-Device, Kernel-Module) nach stdout, ohne /etc/nixos zu berühren.
  nixos-generate-config --show-hardware-config \
    >"$REPO_DIR/hosts-nixos/$HOST/hardware-configuration.nix"
  # Flakes sehen nur von git getrackte Dateien — neue Host-Dateien stagen,
  # sonst ignoriert `nixos-rebuild --flake` den frischen Host.
  git -C "$REPO_DIR" add "hosts-nixos/$HOST"
fi

REBUILD_CMD="sudo nixos-rebuild switch --flake $REPO_DIR#$HOST"
say "Rebuild-Befehl:"
printf '    %s\n' "$REBUILD_CMD"

read -r -p "Jetzt direkt ausführen? [y/N]: " RUN </dev/tty
case "$RUN" in
  [yY]*)
    say "Starte Rebuild …"
    # shellcheck disable=SC2086 # REBUILD_CMD soll in seine Argumente aufgespalten werden
    eval "$REBUILD_CMD"
    ;;
  *)
    say "Übersprungen. Befehl oben bei Bedarf selbst ausführen."
    ;;
esac
