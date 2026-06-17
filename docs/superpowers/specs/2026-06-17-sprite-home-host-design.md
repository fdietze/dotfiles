# Permanenter Sprite-Host + konsistentes hosts-`<builder>`/-Schema

## Ziel

Einen permanenten, benannten Home-Manager-Host für die Fly Sprite einrichten —
analog zu korken (eigene Datei, benannte Config), aber als reine
`homeManagerConfiguration`. Agenten laufen vorerst **unsandboxed** (vanilla),
weil nono/Landlock-Eignung auf der Sprite-VM noch nicht geprüft ist.

Gleichzeitig die Host-Verzeichnisse konsistent nach Builder-Typ benennen:
`hosts-nixos/`, `hosts-home/`, `hosts-nix-on-droid/`.

## Kontext

Die Sprite ist eine Fly Sprite (https://docs.sprites.dev/): Ubuntu microVM,
single-user nix, fester User `sprite`, Hostname `remote-ai`, persistentes
Dateisystem. Aktiviert wird per `home-manager switch` gegen die GitHub-Flake.

Aktueller Zwischenstand: `homeConfigurations."sprite@x86_64-linux" = mkHome
"x86_64-linux" "sprite"`. Seit der letzten flake-Änderung importiert `mkHome`
aber `ai-agents/default.nix` (nono-**sandboxed**). Das widerspricht "kein
Sandboxing for now" und ist der falsche Abstraktionspfad: `mkHome` ist laut
README der ephemere "quick shell on any box"-Pfad (`felix@arch`), kein
benannter permanenter Host.

### Warum getrennte Verzeichnisse pro Builder

`hosts/` wird in flake.nix auto-entdeckt (`hostNames`) und an
`nixpkgs.lib.nixosSystem` übergeben, das `default.nix` +
`hardware-configuration.nix` erwartet. Andere Builder passen nicht in diesen
Vertrag:

| Verzeichnis (neu)      | Builder                                    | Aktivierung          | Flake-Output                  |
|------------------------|--------------------------------------------|----------------------|-------------------------------|
| `hosts-nixos/`         | `nixpkgs.lib.nixosSystem`                  | `nixos-rebuild`      | `nixosConfigurations.<n>`     |
| `hosts-nix-on-droid/`  | `nix-on-droid.lib.nixOnDroidConfiguration` | `nix-on-droid switch`| `nixOnDroidConfigurations.<n>`|
| `hosts-home/`          | `home-manager.lib.homeManagerConfiguration`| `home-manager switch`| `homeConfigurations.<n>`      |

korken bleibt in `hosts-nix-on-droid/` (nicht `hosts-home/`), weil seine
Top-Level-Abstraktion nix-on-droid ist (`user.*`, `build.activation*`,
`environment.packages`, Android-proot-Aktivierung) und *enthält* nur eine
Home-Manager-Config. Es ist keine `homeManagerConfiguration`. Der Sprite-Host
dagegen ist genau eine — passt in `hosts-home/`.

Verzeichnisname = Builder-Typ. Selbsterklärend, keine Überraschungen.

## Architektur

### 1. Drei-Ordner-Rename (reiner Move, keine Funktionsänderung)

Alle via `git mv` (History erhalten):

- `hosts/` → `hosts-nixos/`
- `nix-on-droid/` → `hosts-nix-on-droid/`
- neu anlegen: `hosts-home/`

### 2. Neue Host-Datei `hosts-home/sprite.nix`

Schlank, analog zu korkens eigener Datei. Listet ihre Profile selbst (wie
korken), setzt User/Home (überschreibt shell-cores `mkDefault`-felix):

```nix
# Fly Sprite (https://docs.sprites.dev/): Ubuntu microVM, single-user nix,
# fester User "sprite", Hostname "remote-ai". Standalone Home Manager,
# aktiviert mit `home-manager switch`. Agenten unsandboxed (vanilla.nix):
# "kein Sandboxing for now" — nono/Landlock-Eignung auf der VM später prüfen.
{ ... }: {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    ../modules/home-manager/profiles/standalone-extras.nix
  ];
  home.username = "sprite";
  home.homeDirectory = "/home/sprite";
}
```

### 3. Builder `mkHomeHost` in flake.nix

Spiegelt `mkNixOnDroid` (name → Datei + hostLabel + Output). Die pkgs-Instanz
und die meisten extraSpecialArgs sind identisch zu `mkHome`; einziger Zusatz ist
`hostLabel = name` (für stabiles Starship-`STARSHIP_HOST`, da der VM-Hostname
`remote-ai` nichtssagend ist; shell.nix liest `hostLabel`, default `""`).

```nix
mkHomeHost = system: name:
  home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [llm-agents.overlays.default];
    };
    extraSpecialArgs = {
      flake-inputs = inputs;
      nvf = nvf;
      theme = defaultTheme;
      uiFonts = uiFontsFor system;
      hostLabel = name;
    };
    modules = [
      nix-index-database.homeModules.nix-index
      ./hosts-home/${name}.nix
    ];
  };
```

`mkHome` (ephemerer `felix@arch`-Pfad) bleibt unverändert. Die Duplikation der
pkgs/extraSpecialArgs-Blöcke wird bewusst akzeptiert (zwei Aufrufer, leicht
unterschiedliche Args) statt eine weitere Abstraktion einzuziehen (KISS, YAGNI).

### 4. Flake-Output

```nix
homeConfigurations.sprite = mkHomeHost "x86_64-linux" "sprite";
```

Explizit, keine Auto-Discovery von `hosts-home/` (wie nix-on-droid; bei einem
Host wäre Auto-Discovery verfrüht — YAGNI).

### 5. Stopgap entfernen

`"sprite@x86_64-linux" = mkHome "x86_64-linux" "sprite"` aus
`homeConfigurations` löschen. Ersetzt durch den benannten `sprite`-Host.

## Pfad-Referenzen anpassen (Teil des Rename-Schritts)

Aktiver Code (muss stimmen):

- `flake.nix`: `./hosts/...` (Z. ~101, 115, 120, 137-138, 151) → `./hosts-nixos/...`;
  `./nix-on-droid/...` (Z. ~191, 197) → `./hosts-nix-on-droid/...`
- `scripts/setup-new-host.sh`: `hosts/` (Z. 68, 72-74, 78, 81) → `hosts-nixos/`
- `ci/proot-bump.nix`: `../nix-on-droid/proot-bumped` → `../hosts-nix-on-droid/proot-bumped`

`ci/` selbst bleibt; nur sein Verweis ändert sich. `proot-bumped` wird von
korken aktiv gebraucht (tty-Fix #515) — bleibt erhalten, wandert nur mit dem
Ordner.

Kommentar-/Doku-Pfade:

- `ci/proot-bump.nix:4`, `.github/workflows/build-proot.yml:1`,
  `hosts-nix-on-droid/proot-bumped/default.nix:11` (Kommentare)
- Live-Docs: `README.md`, `AGENTS.md`, `PHILOSOPHY.md`

Historische Aufzeichnungen bleiben unangetastet (kein Live-Zustand):
`docs/superpowers/plans/*`, `docs/superpowers/specs/*`.

## Verifikation

Reiner Rename → generierter Output muss byte-identisch bleiben:

- vor Rename: `nix build .#nixosConfigurations.gurke.config.system.build.toplevel`
  und `.#nixOnDroidConfigurations.korken.activationPackage` bauen, Store-Pfade
  notieren.
- nach Rename: erneut bauen, mit `nvd diff <alt> <neu>` prüfen dass **keine**
  Änderung (außer ggf. nichts).
- `nix flake check`.
- neuer Host baut: `nix build .#homeConfigurations.sprite.activationPackage`.
- inkrementell bauen während des Refactors, um Fehler früh zu fangen.

## Update-Befehl auf dem Sprite danach

```bash
USER=sprite nix run home-manager -- switch -b backup \
  --flake github:fdietze/dotfiles#sprite
```

(`USER=sprite`, weil der home-manager-Launcher `$USER` liest und `sprite exec`
es nicht setzt; in `sprite console` ist es gesetzt.)

## Nicht im Scope

- nono/Landlock auf der Sprite zum Laufen bringen (späterer Schritt; "for now"
  vanilla).
- Auto-Discovery für `hosts-home/`.
- Sprite-Provisionierung (SSH-Deploy-Key, GSSAPI-ssh_config-Fix) — das sind
  Runtime-Schritte auf der VM, kein Repo-Artefakt.
