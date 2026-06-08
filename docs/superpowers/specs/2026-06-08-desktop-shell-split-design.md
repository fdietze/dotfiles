# Desktop-Shell-Sugar aus shell-core auslagern — Design

Stand: 2026-06-08

## Problem

`modules/home-manager/profiles/shell-core.nix` ist als strikt headless-tauglicher
Core gedacht (von `shared.nix`, den standalone `homeConfigurations` und dem
Template-Host importiert). Er enthält aber noch desktop-bezogene Shell-Aliase und
-Envs, die (a) im headless-Profil semantisch sinnlos sind und (b) Desktop-Pakete
ins standalone-Closure ziehen (`firefox` über `BROWSER`, `zbar` über `qrscan`,
`espeak` über `online-wait`).

## Ziel

Desktop-bezogene Aliase/Envs aus `shell-core.nix` heraus in Module verschieben,
die **nur `shared.nix`** importiert. Damit:

- `shell-core` bleibt strikt headless.
- gurke bleibt **bitidentisch** (importiert via `shared.nix` weiterhin alles).
- standalone/Template verlieren die Desktop-Aliase und ziehen kein
  `firefox`/`zbar`/`espeak` mehr.

Nicht-Ziel: keine inhaltliche Änderung der Aliase/Envs selbst, nur Umzug.

## Änderungen

### 1. `launchers.nix` (bestehend) — Firefox-Envs

In den bestehenden `home.sessionVariables`-Block (neben `TERMINAL`) ergänzen:

```nix
    BROWSER = "${pkgs.firefox}/bin/firefox";
    MOZ_USE_XINPUT2 = 1; # fix firefox scrolling, enable touchpad gestures
```

`launchers.nix` ist bereits das „cross-desktop application defaults"-Modul mit
`home.sessionVariables` und `pkgs` im Scope; `BROWSER` gehört semantisch zu
`TERMINAL`.

### 2. Neu: `modules/home-manager/profiles/desktop-shell.nix`

Symmetrisch zu `shell-core.nix`: GUI-Session-Shell-Aliase. Setzt
`home.shellAliases = { … }` mit den verschobenen Einträgen:

- `qrscan` (`${pkgs.zbar}` zbarcam, Webcam)
- `feh` (Bildbetrachter)
- `signal-desktop`
- `chromium-no-plugins`
- `tclip` (`xclip`, X11-Clipboard)
- `online-wait` (`${pkgs.espeak}`, Audio-TTS)

Wird von `shared.nix` importiert.

### 3. `shell-core.nix` — entfernen

- aus `home.sessionVariables`: `BROWSER`, `MOZ_USE_XINPUT2` (inkl. des
  auskommentierten `# BROWSER = librewolf`).
- aus `home.shellAliases`: `qrscan`, `feh`, `signal-desktop`,
  `chromium-no-plugins`, `tclip`, `online-wait`.

**Bleibt im Core** (portabel): `online` (reines `ping`), `vb` (Editor-Alias auf
polybar-Config — harmlos ohne polybar), `s`/ddgr, `qr`/qrencode, `tw`/timewarrior
sowie alle reinen Shell-/Repo-Aliase. Der `chromium-no-plugins`-Kommentarblock
(Xft.dpi/Wayland-Scale) wandert mit dem Alias nach `desktop-shell.nix`.

## Bitidentität & Verifikation

gurke importiert via `shared.nix`: `shell-core` + `launchers` + `desktop-shell`.
`home.shellAliases`/`home.sessionVariables` mergen über Module hinweg → gurkes
gemergte Menge unverändert.

- **Refactor-Test:** `nix build .#nixosConfigurations.gurke.config.system.build.toplevel`
  vor/nach, `nvd diff` → delta +0 (mit identischem noctalia-Runtime-Stand, also
  Back-to-Back-Build).
- **Closure-Test:** `nix path-info -r .#homeConfigurations."felix@x86_64-linux".activationPackage`
  enthält danach **kein** `firefox`/`zbar`/`espeak` mehr (vorher prüfen, um die
  Baseline zu kennen).

## Risiken

- `launchers.nix` muss auf allen gurke-Spezialisierungen aktiv sein (ungated),
  sonst verschwindet `BROWSER` auf manchen Desktops → würde der nvd-Test fangen.
- Aliase, die andere Aliase referenzieren (`online-wait` nutzt `online`):
  `online` bleibt im Core, `online-wait` in desktop-shell — auf gurke sind beide
  über `shared.nix` present; standalone hat keines von beiden. Kein Problem.
