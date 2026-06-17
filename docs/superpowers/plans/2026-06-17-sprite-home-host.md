# Permanenter Sprite-Host + hosts-`<builder>`/-Rename — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permanenten Home-Manager-Host `homeConfigurations.sprite` (vanilla agents, eigene Datei) einrichten und Host-Verzeichnisse konsistent nach Builder benennen (`hosts-nixos/`, `hosts-home/`, `hosts-nix-on-droid/`).

**Architecture:** Reiner Verzeichnis-Rename via `git mv` (History erhalten) plus Pfad-Fixes in flake.nix/Skript/CI; danach neuer schlanker Host-Builder `mkHomeHost` analog `mkNixOnDroid`. Korrektheit über Byte-Identität der generierten Closures (nvd) statt Unit-Tests.

**Tech Stack:** Nix Flakes, Home Manager, `git mv`, `nvd` (Closure-Diff), `nix build` (keine Aktivierung).

**Spec:** `docs/superpowers/specs/2026-06-17-sprite-home-host-design.md`

**Wichtige Randbedingungen:**
- Arbeitsbaum ist dirty (fremde actor-swarm-Änderungen an noctalia/opencode/ai-agents/default.nix etc.). Diese **nicht** anfassen; pro Commit nur die jeweils relevanten Pfade stagen. Die fremden Änderungen berühren weder `hosts/` noch `nix-on-droid/`, sind also orthogonal — und bleiben in Baseline- wie Verifikations-Build konstant, sodass `nvd` nur den Rename-Effekt zeigt.
- **Niemals** `nrs`/`nixos-rebuild switch`/`home-manager switch` ausführen. Nur `nix build` (ohne Aktivierung).
- `nix eval`/`nix build` auf dieser lokalen Path-Flake brauchen ggf. `--impure` nicht (Flake-Builds sind pure); `nix build .#...` genügt. Bei "Git tree is dirty"-Warnung: ignorieren.

---

## Task 1: Baseline-Store-Pfade erfassen (vor jeder Änderung)

Zweck: Referenz für die Byte-Identitäts-Prüfung nach dem Rename.

**Files:** keine (nur Build/Notiz).

- [ ] **Step 1: gurke toplevel bauen und Pfad notieren**

Run:
```bash
cd ~/projects/dotfiles
nix build --no-link --print-out-paths .#nixosConfigurations.gurke.config.system.build.toplevel | tee /tmp/baseline-gurke.path
```
Expected: ein `/nix/store/...-nixos-system-gurke-...`-Pfad, gespeichert in `/tmp/baseline-gurke.path`.

- [ ] **Step 2: korken activationPackage bauen und Pfad notieren**

Run:
```bash
nix build --no-link --print-out-paths .#nixOnDroidConfigurations.korken.activationPackage | tee /tmp/baseline-korken.path
```
Expected: ein `/nix/store/...`-Pfad, gespeichert in `/tmp/baseline-korken.path`.

- [ ] **Step 3: nvd verfügbar machen**

Run:
```bash
command -v nvd || echo "use: nix shell nixpkgs#nvd -c nvd ..."
```
Expected: entweder ein Pfad zu `nvd` (ist in packages-cli) oder der Hinweis, dass `nix shell nixpkgs#nvd -c` als Fallback dient. Kein Commit in diesem Task.

---

## Task 2: `hosts/` → `hosts-nixos/` umbenennen

**Files:**
- Move: `hosts/` → `hosts-nixos/` (ganzes Verzeichnis, via `git mv`)
- Modify: `flake.nix` (Zeilen 55, 96, 101, 109-110, 115, 120, 137-138, 151, 221)
- Modify: `scripts/setup-new-host.sh` (Zeilen 68, 72-74, 78, 81)

- [ ] **Step 1: Verzeichnis umbenennen (History erhalten)**

Run:
```bash
cd ~/projects/dotfiles
git mv hosts hosts-nixos
```
Expected: kein Output, `git status` zeigt die Renames unter `hosts-nixos/`.

- [ ] **Step 2: Code-Pfade in flake.nix ersetzen**

Ersetzt alle `./hosts/`-Referenzen (Z. 101, 120, 137-138, 151) und das `readDir ./hosts` (Z. 115):
```bash
sed -i 's|\./hosts/|./hosts-nixos/|g; s|builtins.readDir \./hosts)|builtins.readDir ./hosts-nixos)|g' flake.nix
grep -n '\./hosts' flake.nix
```
Expected: `grep` zeigt nur noch `./hosts-nixos/...` und `./hosts-nix-on-droid/` (letzteres unverändert, kommt erst in Task 3), KEIN nacktes `./hosts/`.

- [ ] **Step 3: Kommentar-Pfade in flake.nix anpassen**

Drei Kommentarzeilen mit nacktem `hosts/`:
- Z. 55: `# cache.numtide.com (siehe Substituter in hosts/gurke/default.nix), kein` → `hosts-nixos/gurke/default.nix`
- Z. 96: `# Arch pro Host aus hosts/<h>/system lesen ...` → `hosts-nixos/<h>/system`
- Z. 109-110: `# Alle Verzeichnisse unter hosts/ außer ...` / `# ... ein hosts/<name>/ anzulegen ...` → `hosts-nixos/`
- Z. 221: `# gurke (und jeder weitere hosts/<name>/) wird auto-entdeckt.` → `hosts-nixos/<name>/`

Mit sed (nur Kommentarzeilen mit `hosts/` ohne `-nixos`/`-nix-on-droid`):
```bash
sed -i 's|\bhosts/gurke|hosts-nixos/gurke|g; s|hosts/<h>/|hosts-nixos/<h>/|g; s|hosts/<name>/|hosts-nixos/<name>/|g; s|unter `hosts/`|unter `hosts-nixos/`|g; s|unter hosts/ |unter hosts-nixos/ |g' flake.nix
grep -n 'hosts/' flake.nix | grep -v 'hosts-nixos\|hosts-nix-on-droid'
```
Expected: zweiter `grep` liefert **nichts** mehr (kein nacktes `hosts/`).

- [ ] **Step 4: setup-new-host.sh anpassen**

```bash
sed -i 's|/hosts/|/hosts-nixos/|g; s|"hosts/|"hosts-nixos/|g' scripts/setup-new-host.sh
grep -n 'hosts' scripts/setup-new-host.sh
```
Expected: alle Treffer zeigen `hosts-nixos/`, kein nacktes `hosts/`.

- [ ] **Step 5: gurke neu bauen und gegen Baseline diffen**

Run:
```bash
NEW=$(nix build --no-link --print-out-paths .#nixosConfigurations.gurke.config.system.build.toplevel)
nvd diff "$(cat /tmp/baseline-gurke.path)" "$NEW" || nix shell nixpkgs#nvd -c nvd diff "$(cat /tmp/baseline-gurke.path)" "$NEW"
```
Expected: nvd meldet **keine** Differenz (leere Paketliste / "0 package(s) added, 0 removed, 0 changed"). Falls Differenz → Pfad-Fix fehlerhaft, korrigieren bevor Commit.

- [ ] **Step 6: Commit (nur Rename + zugehörige Pfad-Fixes)**

```bash
git add hosts-nixos flake.nix scripts/setup-new-host.sh
git commit -m "refactor(hosts): rename hosts/ -> hosts-nixos/ (NixOS builder)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
Expected: Commit enthält nur die `hosts-nixos/`-Renames, flake.nix, setup-new-host.sh — keine fremden dirty-tree-Dateien.

---

## Task 3: `nix-on-droid/` → `hosts-nix-on-droid/` umbenennen

**Files:**
- Move: `nix-on-droid/` → `hosts-nix-on-droid/` (via `git mv`)
- Modify: `flake.nix` (Zeilen 191, 197)
- Modify: `ci/proot-bump.nix` (Zeile 8 Code, Zeile 4 Kommentar)

- [ ] **Step 1: Verzeichnis umbenennen**

```bash
cd ~/projects/dotfiles
git mv nix-on-droid hosts-nix-on-droid
```
Expected: Renames unter `hosts-nix-on-droid/` in `git status`.

- [ ] **Step 2: Code-Pfade in flake.nix ersetzen**

```bash
sed -i 's|\./nix-on-droid/|./hosts-nix-on-droid/|g' flake.nix
grep -n 'nix-on-droid/' flake.nix
```
Expected: nur noch `./hosts-nix-on-droid/...` (Z. 191, 197). Der Flake-Input `nix-on-droid` (ohne Slash-Pfad, `url = "github:...nix-on-droid/master"`, `.lib`, `.overlays`) bleibt unverändert.

- [ ] **Step 3: ci/proot-bump.nix anpassen (Code + Kommentar)**

```bash
sed -i 's|\.\./nix-on-droid/proot-bumped|../hosts-nix-on-droid/proot-bumped|g; s|See nix-on-droid/proot-bumped/|See hosts-nix-on-droid/proot-bumped/|g' ci/proot-bump.nix
grep -n 'nix-on-droid' ci/proot-bump.nix
```
Expected: beide Treffer zeigen `hosts-nix-on-droid/proot-bumped`.

- [ ] **Step 4: korken neu bauen und gegen Baseline diffen**

```bash
NEW=$(nix build --no-link --print-out-paths .#nixOnDroidConfigurations.korken.activationPackage)
nvd diff "$(cat /tmp/baseline-korken.path)" "$NEW" || nix shell nixpkgs#nvd -c nvd diff "$(cat /tmp/baseline-korken.path)" "$NEW"
```
Expected: **keine** Differenz. Falls doch → Pfad-Fix korrigieren bevor Commit.

- [ ] **Step 5: Commit**

```bash
git add hosts-nix-on-droid flake.nix ci/proot-bump.nix
git commit -m "refactor(hosts): rename nix-on-droid/ -> hosts-nix-on-droid/

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
Expected: Commit enthält nur die `hosts-nix-on-droid/`-Renames, flake.nix, ci/proot-bump.nix.

---

## Task 4: `hosts-home/sprite.nix` + `mkHomeHost` + Flake-Output

**Files:**
- Create: `hosts-home/sprite.nix`
- Modify: `flake.nix` (mkHomeHost-Builder einfügen; homeConfigurations: `sprite` hinzu, `sprite@x86_64-linux` entfernen)

- [ ] **Step 1: Host-Datei anlegen**

Create `hosts-home/sprite.nix`:
```nix
# Fly Sprite (https://docs.sprites.dev/): Ubuntu microVM, single-user nix,
# fester User "sprite", Hostname "remote-ai". Standalone Home Manager,
# aktiviert mit `home-manager switch`. Agenten unsandboxed (vanilla.nix):
# "kein Sandboxing for now" — nono/Landlock-Eignung auf der VM später prüfen.
{...}: {
  imports = [
    ../modules/home-manager/profiles/shell-core.nix
    ../modules/home-manager/profiles/ai-agents/vanilla.nix
    ../modules/home-manager/profiles/standalone-extras.nix
  ];
  home.username = "sprite";
  home.homeDirectory = "/home/sprite";
}
```

- [ ] **Step 2: `mkHomeHost`-Builder in flake.nix einfügen**

Direkt **nach** dem `mkHome`-Block (endet mit `};` vor `mkNixOnDroid`) einfügen. Finde die Stelle:
```bash
grep -n 'mkNixOnDroid = deviceName:' flake.nix
```
Füge unmittelbar **vor** dieser Zeile ein (gleiche Einrückungsebene, 4 spaces im `let`):
```nix
    # Benannter, permanenter Standalone-Home-Manager-Host (hosts-home/<name>.nix),
    # aktiviert mit `home-manager switch --flake .#<name>`. Spiegelt mkNixOnDroid:
    # name -> Datei + hostLabel + Output. Die Host-Datei listet ihre Profile
    # selbst (inkl. Agenten-Variante), daher hier nur Builder-Boilerplate.
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
          # Stabiles Starship-STARSHIP_HOST; VM-Hostname (remote-ai) ist nichtssagend.
          hostLabel = name;
        };
        modules = [
          nix-index-database.homeModules.nix-index
          ./hosts-home/${name}.nix
        ];
      };

```

- [ ] **Step 3: Flake-Output anpassen (sprite hinzu, Stopgap weg)**

Finde den homeConfigurations-Block:
```bash
grep -n 'sprite@x86_64-linux\|homeConfigurations = {' flake.nix
```
Ersetze die Stopgap-Zeile + Kommentar **innerhalb** des Blocks. Aktuell:
```nix
      "felix@aarch64-linux" = mkHome "aarch64-linux" "felix";
      # Fly Sprite (https://docs.sprites.dev/): Ubuntu-VM, fester User "sprite".
      "sprite@x86_64-linux" = mkHome "x86_64-linux" "sprite";
```
Neu:
```nix
      "felix@aarch64-linux" = mkHome "aarch64-linux" "felix";
      # Benannte permanente Home-Manager-Hosts (hosts-home/<name>.nix):
      # "home-manager switch --flake .#<name>".
      sprite = mkHomeHost "x86_64-linux" "sprite";
```
WICHTIG: `sprite` bleibt **im** `homeConfigurations = { ... }`-Attrset (als unquoted key `sprite`). NICHT als separates `homeConfigurations.sprite = ...` daneben schreiben — Nix wirft sonst "attribute 'homeConfigurations' already defined". Der Block-Abschluss `};` bleibt unverändert an seiner Stelle. Ergebnis:
```nix
    homeConfigurations = {
      "felix@x86_64-linux" = mkHome "x86_64-linux" "felix";
      "felix@aarch64-linux" = mkHome "aarch64-linux" "felix";
      sprite = mkHomeHost "x86_64-linux" "sprite";
    };
```

- [ ] **Step 4: Syntax prüfen**

```bash
nix flake check --no-build 2>&1 | head -20 || true
nix eval .#homeConfigurations.sprite.config.home.username
```
Expected: `nix eval` gibt `"sprite"` aus. Keine Eval-Fehler.

- [ ] **Step 5: sprite-Host bauen**

```bash
nix build --no-link --print-out-paths .#homeConfigurations.sprite.activationPackage
```
Expected: ein `/nix/store/...-home-manager-generation`-Pfad, Build erfolgreich.

- [ ] **Step 6: Verifizieren dass vanilla agents (kein nono) drin sind**

```bash
P=$(nix build --no-link --print-out-paths .#homeConfigurations.sprite.config.home.path)
ls "$P/bin" | grep -E '^claude$|^vanilla-claude$' ; echo "--- claude wrapper inhalt ---"; cat "$P/bin/claude" | grep -c nono
```
Expected: `claude` existiert, `vanilla-claude` existiert **nicht** (vanilla.nix erzeugt nur `<name>`, kein `vanilla-<name>`); der nono-Grep-Count ist `0` (kein Sandbox-Wrapper).

- [ ] **Step 7: gurke + korken erneut gegen Baseline (Regressionsschutz)**

```bash
nvd diff "$(cat /tmp/baseline-gurke.path)" "$(nix build --no-link --print-out-paths .#nixosConfigurations.gurke.config.system.build.toplevel)" 2>/dev/null || nix shell nixpkgs#nvd -c nvd diff "$(cat /tmp/baseline-gurke.path)" "$(nix build --no-link --print-out-paths .#nixosConfigurations.gurke.config.system.build.toplevel)"
```
Expected: weiterhin **keine** Differenz (mkHomeHost-Zusatz darf gurke nicht beeinflussen).

- [ ] **Step 8: Commit**

```bash
git add hosts-home/sprite.nix flake.nix
git commit -m "feat(hosts-home): add permanent sprite host with vanilla agents

homeConfigurations.sprite via neuem mkHomeHost-Builder; ersetzt den
Stopgap-Eintrag sprite@x86_64-linux. Agenten unsandboxed (vanilla.nix).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Live-Docs + Kommentar-Pfade aktualisieren

**Files:**
- Modify: `README.md` (Z. 52, 65)
- Modify: `AGENTS.md` (Z. 52-53, 57)
- Modify: `PHILOSOPHY.md` (Z. 12)
- Modify: `.github/workflows/build-proot.yml` (Z. 1 Kommentar)
- Modify: `hosts-nix-on-droid/proot-bumped/default.nix` (Z. 11 Kommentar)

Historische Aufzeichnungen (`docs/superpowers/plans/*`, `docs/superpowers/specs/*`) bleiben unangetastet.

- [ ] **Step 1: README.md**

```bash
sed -i 's|`hosts/template/`|`hosts-nixos/template/`|g; s|`hosts/gurke/`|`hosts-nixos/gurke/`|g' README.md
grep -n 'hosts/' README.md | grep -v 'hosts-nixos'
```
Expected: zweiter grep liefert nichts.

- [ ] **Step 2: AGENTS.md**

Ersetze die drei nackten `hosts/<hostname>/` bzw. `hosts/<host>/`:
```bash
sed -i 's|hosts/<hostname>/|hosts-nixos/<hostname>/|g; s|hosts/<host>/|hosts-nixos/<host>/|g' AGENTS.md
grep -n 'hosts/' AGENTS.md | grep -v 'hosts-nixos\|hosts-nix-on-droid'
```
Expected: zweiter grep liefert nichts.

- [ ] **Step 3: PHILOSOPHY.md**

```bash
sed -i 's|`hosts/<hostname>/`|`hosts-nixos/<hostname>/`|g' PHILOSOPHY.md
grep -n 'hosts/' PHILOSOPHY.md | grep -v 'hosts-nixos'
```
Expected: leer.

- [ ] **Step 4: CI-Workflow + proot-bumped-Kommentar**

```bash
sed -i 's|see nix-on-droid/proot-bumped/|see hosts-nix-on-droid/proot-bumped/|g; s|(see nix-on-droid/proot-bumped/)|(see hosts-nix-on-droid/proot-bumped/)|g' .github/workflows/build-proot.yml
sed -i 's|ci/proot-bump.nix and korken|ci/proot-bump.nix and korken|g; s|nix-on-droid/|hosts-nix-on-droid/|g' hosts-nix-on-droid/proot-bumped/default.nix
grep -rn 'nix-on-droid/proot-bumped\|nix-on-droid/korken' .github/workflows/build-proot.yml hosts-nix-on-droid/proot-bumped/default.nix
```
Expected: alle verbliebenen Treffer zeigen `hosts-nix-on-droid/...`. (Bare flake-input-Namen ohne Slash bleiben.)

- [ ] **Step 5: Gesamt-Check auf verwaiste Pfade (nur Live-Dateien)**

```bash
grep -rn -E '(^|[^-])\bhosts/|(^|[^-])\bnix-on-droid/' --include="*.nix" --include="*.sh" --include="*.yml" --include="*.md" . 2>/dev/null | grep -v '\.git/' | grep -v 'docs/superpowers/' | grep -vE 'github:|nix-community/nix-on-droid|\.lib\.|\.overlays|\.nixosModules|\.homeModules|inputs\.|url ='
```
Expected: **leer** (alle aktiven Referenzen migriert; nur historische docs/superpowers/ und Flake-Input-Namen verbleiben, beide bewusst ausgenommen).

- [ ] **Step 6: Commit**

```bash
git add README.md AGENTS.md PHILOSOPHY.md .github/workflows/build-proot.yml hosts-nix-on-droid/proot-bumped/default.nix
git commit -m "docs: update host paths to hosts-<builder>/ scheme

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Abschluss-Verifikation

- [ ] **gurke + korken byte-identisch:** beide nvd-Diffs (Task 2 Step 5, Task 3 Step 4, Task 4 Step 7) zeigten keine Differenz.
- [ ] **sprite baut:** Task 4 Step 5 erfolgreich; `home.username == "sprite"`; vanilla agents (kein nono) bestätigt.
- [ ] **keine verwaisten Pfade:** Task 5 Step 5 grep leer.
- [ ] **dirty-tree-Fremdänderungen unangetastet:** `git status` zeigt die ursprünglichen fremden Modified-Dateien (noctalia/opencode/ai-agents/default.nix/superpowers.nix) weiterhin als unstaged/uncommitted.

**Update-Befehl auf dem Sprite (nach Push auf master):**
```bash
USER=sprite nix run home-manager -- switch -b backup --flake github:fdietze/dotfiles#sprite
```
