# Bootstrap & Shell-Fallback für neue Hosts — Design

Stand: 2026-06-06

## Problem

Die README-Installationsanleitung ist veraltet und kennt nur einen einzigen,
hartcodierten Host (`gurke`). Es gibt keinen Weg, das Setup auf einer Maschine
in Betrieb zu nehmen, die noch nicht in `nixosConfigurations` definiert ist,
und keinen schnellen Weg, nur die Shell-Umgebung auf einer beliebigen Box zu
bekommen.

Annahme: Die Anleitung wird **immer auf einem bereits laufenden NixOS**
ausgeführt.

## Ziele

Drei Einstiegspunkte:

- **A — Ephemerale/permanente Shell auf beliebiger Box** (standalone Home
  Manager), zeigt direkt auf das GitHub-Flake, ohne Clone.
- **B — Definierter Host** (wie `gurke`): volles NixOS+HM-Setup über das Script
  (Repo muss geklont werden).
- **C — Neuer, noch nicht definierter Host**: generisches Shell-Profil über
  einen Template-Host, eingerichtet über dasselbe Script.

Beide gängigen Architekturen werden unterstützt: `x86_64-linux` und
`aarch64-linux`.

Nicht-Ziel: kein Desktop, keine Disk-/LUKS-Verwaltung im Fallback. Wer einen
Host behalten will, promotet ihn manuell (Desktops, `local.nix`) wie `gurke`.

## Leitprinzipien

- KISS/YAGNI/SoC. Minimal-invasiv. `gurke` bleibt funktional unverändert.
- Das Setup-Script bleibt simpel und editiert **kein** Nix.
- Quelle der Wahrheit bleibt das Flake.

---

## 1. Refactor: Shell-Core herausziehen (Enabler, zuerst & separat committen)

Heute vermischt `modules/home-manager/shared.nix` portable CLI-Konfiguration mit
GUI-/Desktop-Konfiguration (GUI-Terminals, gtk, keepassxc, espanso, chromium,
stylix, theme-switching, icon-themes, launchers, wallpaper). `shell.nix` selbst
ist bereits sauber (nur `config` + `pkgs`).

**Änderung:** Neues Modul `modules/home-manager/profiles/shell-core.nix`, das das
portable, headless-taugliche Subset bündelt:

- `shell.nix` (zsh, zoxide, Aliases)
- `git.nix`
- `dotfiles.nix`
- direnv, fzf, eza, ripgrep, bat
- den CLI-Teil aus `packages.nix`
- neovim via `nvf.nix`

**Nicht** im Core: stylix, theme-switching, icon-themes, launchers, wallpaper,
GUI-Terminals (ghostty/alacritty/kitty/wezterm), gtk, pointerCursor, keepassxc,
espanso, udiskie, chromium, librewolf, qutebrowser, blueman/mpris/playerctld.

`shared.nix` importiert künftig `profiles/shell-core.nix` und behält den
GUI-/Desktop-Teil. Ergebnis: gurkes generierte Konfiguration bleibt
**bitidentisch**.

### Teil-Aufgaben des Refactors

- `packages.nix` in CLI- vs. GUI-Pakete auftrennen. Der CLI-Teil wandert in den
  Core (oder ein vom Core importiertes `packages-cli.nix`), der GUI-Teil bleibt
  im desktop-seitigen Pfad. Bei Unsicherheit ein Paket dem GUI-Teil zuordnen —
  der Core soll wirklich nur headless-Nützliches enthalten.
- `nvf.nix` braucht die Argumente `nvf` (Flake-Input) und `theme`. Der Core
  liefert `theme = "dark"` als Default (siehe Theme-Abschnitt).
- Alle übrigen vom Core importierten Module dürfen nur `config`/`pkgs`/`lib` und
  die im Core bereitgestellten Args (`theme`, `flake-inputs`/`nvf`) erwarten.

### Verifikation

Vor und nach dem Refactor `nvd diff` der gurke-Generation. Beim Vergleich von
Spezialisierungen auf
`/nix/var/nix/profiles/system/specialisation/<name>` ankern. Der Refactor wird
**vor** allem anderen committet.

---

## 2. Theme im Shell-Core

`nvf` nutzt **kein** stylix: in `modules/home-manager/stylix.nix` sind
`targets.neovim.enable = false` und `targets.nvf.enable = false`. Neovim themt
sich vollständig selbst über das `theme`-Argument
(`"dark"` → tokyonight-storm, `"light"` → catppuccin-latte) und flippt zur
Laufzeit über eine Trigger-Datei (relevant nur auf noctalia).

stylix färbt ausschließlich GUI-Terminals/gtk/qt auf themed Desktops. Da der
Shell-Core keine GUI-Terminals enthält, ist stylix dort irrelevant.

**Entscheidung:** Der Shell-Core setzt `theme = "dark"` als Default (über
`extraSpecialArgs` bzw. `mkHome`/`mkHost`). Das entspricht exakt dem
Build-Zeit-Verhalten der noctalia-Spezialisierung. Auf einer headless-Box ohne
noctalia-Trigger bleibt es schlicht dark. Keine zusätzliche Komplexität, kein
stylix.

---

## 3. Flake: Auto-Discovery + Multi-Arch-Helper

### Auto-Discovery

`nixosConfigurations` wird aus `builtins.readDir ./hosts` generiert: jedes
Unterverzeichnis (außer `template`) wird zu einem Host. Der hartcodierte
`gurke`-Block entfällt; `gurke` wird damit ebenfalls auto-entdeckt.

`template` wird übersprungen (kein lauffähiger Host — keine
`hardware-configuration.nix`).

Konsequenz: Das Setup-Script muss `flake.nix` **nicht** editieren. Einen neuen
Host anlegen heißt: Verzeichnis unter `hosts/` erstellen.

### Architektur pro Host

Jeder Host trägt eine kleine Datei `hosts/<h>/system` mit seinem System-String
(`x86_64-linux` oder `aarch64-linux`). Fehlt sie, gilt Default `x86_64-linux`.

Begründung gegen Arch im `default.nix` (`nixpkgs.hostPlatform`):
`nixpkgs.lib.nixosSystem` braucht `system` **bevor** die Module ausgewertet
werden, und das Flake baut `uiFonts` pro System im äußeren Scope — die Arch aus
dem Modul zurückzulesen erzeugt ein Henne-Ei-Problem. Die `system`-Datei umgeht
das ohne weiteren Refactor. `gurke/system` = `x86_64-linux`. Das Script schreibt
die Datei für neue Hosts mit der erkannten Architektur.

### Helper

- `mkHost { hostName, system }`:
  - liest optional `hosts/<h>/local.nix` (falls vorhanden → `hostLocal`),
  - baut `uiFonts` aus `nixpkgs.legacyPackages.<system>`,
  - importiert `hosts/<h>/default.nix` + `hosts/<h>/hardware-configuration.nix`,
  - bindet das `home-manager`-NixOS-Modul ein und setzt `extraSpecialArgs`
    (`flake-inputs`, `hostLocal`, `uiFonts`, `theme`).
- `mkHome { system }`:
  - baut eine standalone `homeManagerConfiguration` mit
    `pkgs = nixpkgs.legacyPackages.<system>`,
  - importiert **nur** `profiles/shell-core.nix`,
  - setzt `extraSpecialArgs` (`theme = "dark"`, `flake-inputs`/`nvf`, `uiFonts`).

### Outputs

```
nixosConfigurations = <auto aus hosts/*, via mkHost>;   # inkl. gurke
homeConfigurations = {
  "felix@x86_64-linux" = mkHome { system = "x86_64-linux"; };
  "felix@aarch64-linux" = mkHome { system = "aarch64-linux"; };
};
```

Der bereits vorhandene auskommentierte `homeConfigurations.felix`-Block wird
durch obige ersetzt.

---

## 4. Template-Host (`hosts/template/`)

Minimaler, desktop-freier NixOS-Host als Vorlage für unkonfigurierte Maschinen.

- `default.nix`:
  - Flakes/nix-command an,
  - User `felix` mit zsh-Login-Shell,
  - `home-manager`-Modul (über `mkHost`),
  - Basis-Netzwerk + openssh,
  - **kein** Desktop, **kein** `my.desktop`/`my.theme`-Zwang,
  - kein `nixos-hardware`-Import (generischer Host).
- `home.nix`: importiert **nur** `../../modules/home-manager/profiles/shell-core.nix`.
- **Keine** `hardware-configuration.nix` im Repo — wird beim Kopieren generiert.
  Ein Kommentar/`.gitkeep` dokumentiert das.
- **Kein** `local.nix` (keine LUKS/Disk-UUIDs).
- **Kein** `system` (Default greift; das Script schreibt die Datei beim Anlegen).

Auto-Discovery überspringt `template` explizit.

---

## 5. Setup-Script (`scripts/setup-new-host.sh`)

Wird über `bash <(curl -fsSL <raw-url>/scripts/setup-new-host.sh)` ausgeführt
(Process Substitution hält stdin am Terminal, vermeidet das
„halb-heruntergeladenes-Script"-Risiko und erlaubt interaktives `read`).

Raw-URL: `https://raw.githubusercontent.com/fdietze/dotfiles/master/scripts/setup-new-host.sh`

Eigenschaften: idempotent, sudo-frei bis zum letzten Schritt, editiert kein Nix.

### Ablauf

1. `git` sicherstellen (sonst über `nix-shell -p git` re-exec/wrap).
2. Repo per https nach `~/projects/dotfiles` klonen (skip, falls vorhanden).
3. **Fragen** (via `/dev/tty`): *NixOS + Home Manager* oder *nur Home Manager*?
4. **Nur HM:**
   - `arch=$(nix eval --raw --impure --expr builtins.currentSystem)` (oder aus
     `uname -m` abgeleitet),
   - `home-manager switch --flake ~/projects/dotfiles#felix@$arch`
     (über `nix run home-manager -- …`, falls `home-manager` nicht im PATH).
5. **NixOS + HM:**
   - `host=$(hostname)`,
   - falls `hosts/$host` existiert (definierter Host wie `gurke`): nichts
     generieren,
   - sonst: `cp -r hosts/template hosts/$host`,
     `echo "$arch" > hosts/$host/system`,
     `nixos-generate-config --show-hardware-config > hosts/$host/hardware-configuration.nix`,
   - `git -C ~/projects/dotfiles add hosts/$host` (Flakes sehen untracked
     Dateien nicht),
   - den exakten Befehl ausgeben:
     `sudo nixos-rebuild switch --flake ~/projects/dotfiles#$host`,
   - via `/dev/tty` fragen, ob direkt ausführen; bei „ja" ausführen.

`nixos-generate-config --show-hardware-config` (verifiziert per man page) druckt
die Hardware-Config nach stdout, ohne Dateien zu schreiben — erkennt
Filesystems, Swap, Boot-Device, Kernel-Module. Kein Kopieren aus `/etc/nixos`.

### Header

Das Script trägt einen Kommentar-Header, der erklärt, was es tut und dass es
über `bash <(curl …)` gedacht ist.

---

## 6. README-Neufassung

Abschnitt „My Installation" durch drei klar getrennte Pfade ersetzen:

- **A — Schnelle Shell auf beliebiger Box** (kein Clone, ephemeral/permanent):
  ```bash
  nix run home-manager -- switch \
    --flake github:fdietze/dotfiles#felix@x86_64-linux
  # aarch64: #felix@aarch64-linux
  ```
- **B — Definierter Host** (z. B. gurke) bzw. **C — neuer Host**, beide über das
  Script:
  ```bash
  bash <(curl -fsSL https://raw.githubusercontent.com/fdietze/dotfiles/master/scripts/setup-new-host.sh)
  ```
  Das Script klont das Repo und fragt nach NixOS+HM vs. nur HM; bei einem bereits
  definierten Hostnamen wird dieser direkt gebaut, sonst ein neuer Host aus dem
  Template erzeugt.

Promotion-Hinweis: „Neuen Host behalten → Desktops/`local.nix` wie bei `gurke`
ergänzen."

Die bestehende WARNING („instructions for myself, not for you") bleibt.

---

## Reihenfolge der Umsetzung (jeweils einzeln committen)

1. Refactor Shell-Core extrahieren; `nvd diff` gurke = identisch.
2. `hosts/<h>/system` einführen (`gurke/system`); Auto-Discovery + `mkHost` im
   Flake; `nvd diff` gurke = identisch.
3. `mkHome` + `homeConfigurations."felix@<arch>"`.
4. `hosts/template/`.
5. `scripts/setup-new-host.sh`.
6. README-Neufassung.

## Risiken / offene Detailpunkte

- CLI-/GUI-Trennung in `packages.nix` braucht Sorgfalt; im Zweifel GUI.
- `curl` ist auf einem minimalen NixOS evtl. nicht installiert; README/Script
  nennen `nix-shell -p curl` als Fallback.
- Ephemerale Boxen haben kein `~/projects/dotfiles`; auf das Repo zeigende
  Aliases/`sessionPath`-Einträge sind dort wirkungslos, aber harmlos.
- `nvf.nix` muss im Core ohne Desktop-Kontext bauen; der `theme = "dark"`-Default
  muss alle dort referenzierten Pfade abdecken.
