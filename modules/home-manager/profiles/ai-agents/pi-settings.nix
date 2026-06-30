# Pi global settings (~/.pi/agent/settings.json) als gepflegte Repo-Quelle.
#
# Pi schreibt diese Datei zur Laufzeit zurück (z.B. lastChangelogVersion, /settings-
# Edits), daher KEIN read-only Store-Symlink wie AGENTS.md, sondern ein out-of-store
# Symlink direkt aufs Working Tree: Pis Schreibvorgänge landen als git-Diffs im Repo.
# Gleiches Muster wie noctalias GUI-getriebene settings.toml (desktops/noctalia-niri.nix).
#
# Kein churn-Filter: lastChangelogVersion ändert sich nur bei pi-Updates (selten) —
# der gelegentliche Bump wird einfach mitcommittet (KISS). Lock-Dateien landen unter
# ~/.pi/agent/settings.json.lock (logischer Pfad, echtes Verzeichnis), nicht im Repo.
{config, ...}: {
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.dotfilesDir}/home/pi/settings.json";
}
