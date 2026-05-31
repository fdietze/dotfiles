# cull — Foto/Video-Durchsicht & Aussortierung

Datum: 2026-05-31

## Zweck

Ein Tool `home/bin/cull` zum schnellen Durchsehen und Aussortieren von Urlaubsfotos
und -videos im aktuellen Verzeichnis. Vollbild, aspect-korrekter Auto-Zoom, Foto+Video,
Navigation per Pfeiltasten, schnelle Aktionen zum Wegwerfen/Sortieren mit visuellem
Feedback, permanente Anzeige von Aufnahmedatum/-zeit.

## Entscheidungen (mit Nutzer abgestimmt)

- **Datumsquelle:** EXIF mit Fallback. Pro Datei erstes vorhandenes von
  `DateTimeOriginal → CreateDate → MediaCreateDate → FileModifyDate` via `exiftool`.
- **Scope:** strikt `pwd`, nicht rekursiv. Keine Argumente.
- **`<Del>`:** `mv` der Datei nach `<pwd>/trash/`.
- **Implementierung:** bash-Launcher + eingebettetes mpv-Lua-Script.
- **Name:** `cull`.

## Architektur

Zwei Teile, ein Deliverable (`home/bin/cull`):

1. **bash-Launcher** — sammelt/sortiert Dateien, startet mpv.
2. **mpv-Lua-Script** — zur Laufzeit in tmp geschrieben, steuert Keybindings, OSD,
   Dateiaktionen. mpv ist das richtige Werkzeug, weil es Bilder UND Videos nativ
   anzeigt; die Aktionen müssen innerhalb des laufenden mpv passieren → Lua (mpv-nativ).

### Launcher (bash, `set -Eeuo pipefail`)

1. `command -v mpv exiftool` prüfen (Fehler mit klarer Meldung wenn fehlt).
2. Dateien in `pwd` (nicht rekursiv) nach Endung filtern, case-insensitiv:
   - Bilder: `jpg jpeg png heic webp gif tiff tif bmp`
   - Videos: `mp4 mov mkv avi webm m4v`
3. **Datum im Batch** mit einem `exiftool`-Aufruf über alle Dateien:
   - `-d` Format liefert sortierbaren Key + lesbares Anzeige-Datum.
   - Pro Datei erstes nicht-leeres der Tag-Kette (oben).
   - Ausgabe: `sortkey \t anzeige-datum \t pfad`.
4. Nach `sortkey` aufsteigend sortieren (`sort`). Leere Liste → Meldung + Exit 0.
5. Anzeige-Datum je Pfad in tmp-Mapfile (`$XDG_RUNTIME_DIR/cull-dates.XXXX`) schreiben,
   damit das Lua-Script nicht neu rechnet.
6. Lua-Script in tmp schreiben (`$XDG_RUNTIME_DIR/cull-script.XXXX.lua`) **mit
   Pflicht-Header-Kommentar** (writer = `cull`, da Runtime-generiert).
7. mpv starten:
   ```
   mpv --fullscreen --loop-file=inf --image-display-duration=inf --no-osc \
       --script=<tmp.lua> --script-opts=cull-datefile=<tmp.map> -- <dateien...>
   ```
8. `trap` räumt beide tmp-Dateien beim Exit auf.

### mpv-Lua-Script

- **Auto-Zoom:** mpv-Default skaliert Bild/Video aspect-korrekt ins Fenster
  (größere verkleinert, kleinere vergrößert). Kein Extra-Code nötig.
- **Bilder bleiben stehen:** `--image-display-duration=inf` (keine Auto-Weiterschaltung).
- **Videos loopen:** `--loop-file=inf` (Bilder als Einzelframe davon unberührt).
- **Navigation:** `LEFT` → `playlist-prev`, `RIGHT` → `playlist-next`
  (überschreibt mpv-Default-Seek bewusst, wie vom Nutzer gewünscht).
- **`DEL`:** aktuelle Datei (`path`-Property) → `mkdir -p <pwd>/trash` + `mv` dorthin,
  dann `playlist-remove current` → springt automatisch zum nächsten. Feedback `→ trash`.
- **`1` / `2`:** `mkdir -p <pwd>/1|2` + `cp` der aktuellen Datei dorthin. Bleibt stehen.
  Feedback `→ 1 ✓` / `→ 2 ✓`.
- **Permanentes Datum unten:** ASS-Overlay via `mp.create_osd_overlay("ass-events")`,
  bottom-center (`\an2`), aktualisiert bei jedem `file-loaded`-Event aus dem Mapfile.
- **Feedback-Bestätigung:** zusätzliche kurze farbige `mp.osd_message(...)` (~1s) bei
  jeder Aktion (trash/1/2), getrennt vom permanenten Datums-Overlay.
- **Quoting:** Dateipfade in Shell-Kommandos korrekt escapen (mpv liefert evtl.
  relative Pfade; `pwd`-Basis + saubere Quotes).

## Fehlerbehandlung

- Fehlende Dependency (mpv/exiftool): klare Meldung, Exit 1.
- Keine passenden Dateien in pwd: Meldung, Exit 0.
- `mv`/`cp` schlägt fehl: Feedback-OSD signalisiert Fehler (rot), Datei bleibt in Playlist.

## Dependencies

- `mpv`, `exiftool` — ggf. in `modules/home-manager/packages.nix` ergänzen
  (separater, eigener Schritt/Commit).

## Bewusst weggelassen (YAGNI)

- Rekursion, dir-Argument, konfigurierbare Zielordner.
- Undo-Stack (trash ist bereits reversibel per Hand).
- rust-script-Launcher (mpv erzwingt Lua; bash-Launcher ist simpelste konsistente Wahl).
