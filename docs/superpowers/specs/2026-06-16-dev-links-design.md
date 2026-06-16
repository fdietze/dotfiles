# Temporäre Dev-Links (`my.devLinks`)

## Problem

Home-Manager-verwaltete Dateien (z.B. pi-Extensions) sind read-only Symlinks
in den Nix-Store. Jede Änderung erfordert einen `nrs`/Home-Manager-Switch, bevor
sie getestet werden kann — langsame Feedback-Schleife.

Gleichzeitig sind heute `home/config/opencode/opencode.jsonc` und
`home/config/nono/profiles/agent.json` *dauerhaft* per `mkOutOfStoreSymlink`
out-of-store verlinkt, nur um sie ohne Rebuild editieren zu können. Das
widerspricht dem Ziel „der Store ist die Wahrheit, alles reproduzierbar".

## Ziel

- **Default = voll reproduzierbar:** keine permanenten out-of-store-Links.
- Ein **allgemeiner, temporärer Schalter**, um beliebige repo-verwaltete Dateien/
  Verzeichnisse für schnelles Feedback live ans Working Tree zu linken.
- Beim Aktivieren genau **ein** Rebuild; danach beliebig oft editieren + `/reload`
  (pi) bzw. Programm-Reload ohne weiteren Rebuild.
- Beim Deaktivieren genau ein Rebuild → zurück zur gepinnten Store-Kopie.

Nicht-Ziel: laufzeit-beschreibbare Verzeichnisse (z.B. `~/.config/noctalia`,
in das noctalia selbst Theme/Settings schreibt). Die bleiben aus eigenem,
berechtigtem Grund out-of-store und sind nicht Teil dieses Mechanismus.

## Design

### Option `my.devLinks`

- Typ: `listOf str`, Default `[]`.
- Inhalt: **repo-relative Pfade ab Repo-Wurzel**, exakt das, was man zum Editieren
  eingibt. Beispiele:
  - `"modules/home-manager/profiles/ai-agents/pi-extensions/context-prune.ts"`
  - `"modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm"`
  - `"home/config/opencode/opencode.jsonc"`

### Gemeinsamer Helper `mkSource`

Eine Funktion `mkSource relPath storePath`:

- `relPath ∈ config.my.devLinks` → `config.lib.file.mkOutOfStoreSymlink
  "${repoDir}/${relPath}"` (Live-Link ans Working Tree)
- sonst → `storePath` (gepinnte Store-Kopie, bisheriges Verhalten)

`repoDir = "${config.home.homeDirectory}/projects/dotfiles"` (bestehendes Muster
aus `dotfiles.nix`).

Konsumenten:

- **`dotfiles.nix` / `collectFiles`:** statt `source = path` wird die Quelle über
  `mkSource` bestimmt. Dafür muss `collectFiles` den repo-relativen Pfad kennen
  (Collect-Root-Präfix einbeziehen, z.B. `home/config` + relPath).
- **`pi-extensions.nix`:** statt `value.source = dir + "/${name}"` ebenfalls über
  `mkSource` mit dem repo-relativen Pfad
  `modules/home-manager/profiles/ai-agents/pi-extensions/${name}`.

Wie der Helper geteilt wird (z.B. via `_module.args` oder ein `config.my.lib.*`
Attribut) ist Implementierungsdetail; Ziel ist eine einzige Definition ohne
Duplikat-Logik.

### `opencode.jsonc`

Verliert seinen permanenten `mkOutOfStoreSymlink`-Override in `dotfiles.nix` und
wird normaler `collectFiles`-Eintrag (Store-Default). Über `my.devLinks`
dev-linkbar wie jede andere Datei.

### `agent.json` wird nix-generiert

Statt out-of-store-Link wird `agent.json` aus der Repo-Datei generiert und als
normaler Store-Link verlinkt:

1. Basis = `builtins.fromJSON (builtins.readFile
   ./home/config/nono/profiles/agent.json)`. Die Repo-Datei bleibt die gepflegte
   Quelle der allow/deny-Regeln.
2. Für jeden Pfad in `my.devLinks` wird der absolute Repo-Pfad
   (`${repoDir}/${relPath}`) an die passende Sandbox-Liste angehängt:
   - Verzeichnis → `filesystem.read`
   - Einzeldatei → `filesystem.read_file`

   (nono-Semantik verifiziert via `nono profile guide`: `read` = read-only
   Verzeichnisse, `read_file` = read-only Einzeldateien.) Den Typ bestimmt Nix
   über `builtins.readDir`/`pathExists`.
3. Ergebnis via `(pkgs.formats.json {}).generate` in den Store, normaler
   Store-Link nach `~/.config/nono/profiles/agent.json`.

Damit folgen die Sandbox-Leserechte automatisch `my.devLinks` — im **selben**
Rebuild, der die Datei-Links umschaltet. Keine Extra-Rebuilds, kein zweiter Ort
zum Pflegen.

## Bewusste Konsequenzen

- **`agent.json` ist nicht mehr live editierbar.** Änderungen an den Sandbox-
  Basisregeln (allow/deny) brauchen wieder einen Rebuild. Bewusst akzeptiert:
  konsistent mit „kein out-of-store per Default", und bei sicherheitsrelevanten
  Sandbox-Regeln ist ein deliberater Rebuild sogar wünschenswert.
- **Während dev-mode** ist die Wahrheit für den Inhalt der gelisteten Pfade das
  Working Tree, nicht der Store — inhärent bei „kein Rebuild pro Edit", bewusst
  temporär.
- **Sandbox-Vergrößerung** nur, solange ein Pfad in `my.devLinks` steht; eng auf
  den jeweiligen Repo-Pfad begrenzt, read-only, keine Secrets (die liegen in
  keepassxc).

## Workflow

1. `my.devLinks = [ "modules/.../pi-extensions/context-prune.ts" ];` setzen →
   `nrs` einmal.
2. Beliebig oft editieren im Repo + `/reload` in pi. Kein Rebuild.
3. Extension stabil → Pfad aus der Liste entfernen → `nrs` → zurück zur
   gepinnten Store-Kopie; Sandbox-Read-Recht fällt automatisch weg.

## Verifikation

- `nrs` mit leerer `my.devLinks` → `~/.pi/agent/extensions/*` und
  `~/.config/{opencode/opencode.jsonc,nono/profiles/agent.json}` zeigen in den
  Store (keine out-of-store-Links außer noctalias Runtime-Dir).
- `my.devLinks = [ <pfad> ]` + `nrs` → genau dieser Link zeigt ins Repo-Working-
  Tree; `agent.json` enthält den passenden `read`/`read_file`-Eintrag.
- `nono profile show agent` bestätigt die abgeleiteten Read-Pfade.
- Edit der dev-gelinkten Datei + `/reload` in pi greift ohne Rebuild.
