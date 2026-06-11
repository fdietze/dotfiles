# Design Spec: Sandboxed AI-Agent-Abstraktion + nono-Profil im Repo

## Kontext

`claude` und `opencode` werden aktuell in `modules/home-manager/profiles/packages-cli.nix`
jeweils inline als `writeShellScriptBin` in die nono-Sandbox gewickelt (Profil
`claude`), plus je eine un-sandboxed `vanilla-*`-Variante. Das sind vier fast
identische Blöcke. Wir wollen zwei weitere Agents hinzufügen (`codex`,
`pi-coding-agent`), was die Duplikation auf acht Blöcke triebe. Die "Rule of
Three" ist überschritten — wir abstrahieren jetzt.

Gleichzeitig liegt das nono-Profil als loser, nicht versionierter Zustand unter
`~/.config/nono/profiles/claude.json`. Es soll ins Repo wandern und per
out-of-store-Symlink generiert werden (live editierbar, versioniert), und dabei
von `claude` auf den generischen Namen `agent` umbenannt werden.

## Anforderungen

1. **`mkAgent`-Helper** abstrahiert die Wrapper-Erzeugung: erzeugt pro Agent den
   sandboxed `<name>` *und* automatisch `vanilla-<name>`.
2. **Vier Agents**: `claude`, `opencode`, `codex`, `pi` (Binary von
   `pi-coding-agent`).
3. **Geteiltes nono-Profil** `agent` für alle (vormals `claude`).
4. **Profil ins Repo** unter `home/config/nono/profiles/agent.json`, generiert per
   `config.lib.file.mkOutOfStoreSymlink` nach `~/.config/nono/profiles/agent.json`.
5. **Resource-Priorität** (`ionice -c 3` + `nice -n 19`) bleibt für beide
   Varianten erhalten.
6. **Eigenes Modul** `modules/home-manager/profiles/ai-agents.nix`, importiert von
   `shell-core.nix`. `packages-cli.nix` wird wieder reine Paketliste.
7. **Verhaltenstreue**: Das aktuelle Verhalten der bestehenden Wrapper bleibt
   bit-für-bit erhalten (siehe `env`/`yolo`-Trennung).

## Architektur

### Neues Modul `modules/home-manager/profiles/ai-agents.nix`

Signatur `{ config, lib, pkgs, ... }`. Enthält:

- `repoDir = "${config.home.homeDirectory}/projects/dotfiles";` (lokal, wie in
  shell-core).
- Den `mkAgent`-Helper im top-level `let`.
- `home.packages = lib.concatLists [ ... ]` mit den vier `mkAgent`-Aufrufen.
- Den nono-Profil-Symlink via `home.file`.

`shell-core.nix` bekommt `./ai-agents.nix` in seine `imports`. Die vier inline
Wrapper-Blöcke (`claude`, `vanilla-claude`, `opencode`, `vanilla-opencode`) werden
aus `packages-cli.nix` entfernt; die `++ [ ... ]`-Konkatenation dort entfällt,
sodass nur die reine `home.packages = (with pkgs; [ ... ])`-Liste bleibt. `nono`
und `bubblewrap` bleiben als Pakete in `packages-cli.nix`.

### `mkAgent`-Helper

```nix
let
  # Niedrige CPU/IO-Priorität, damit Agent-Subprozesse interaktive Arbeit nicht
  # aushungern.
  prio = "${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19";

  # Wickelt einen AI-Coding-Agent: sandboxed `<name>` (nono, geteiltes Profil
  # `agent`) plus un-sandboxed Escape-Hatch `vanilla-<name>`. Beide behalten prio.
  #   env  -> Prelude (export-Zeilen), gilt für BEIDE Varianten
  #   yolo -> Flags, die die agent-eigenen Permission-Prompts abschalten; NUR
  #           in der sandboxed Variante, da der Schutz dort von nono kommt.
  #           Ohne Sandbox (vanilla) bleiben die agent-eigenen Prompts intakt.
  mkAgent = { name, bin, env ? "", yolo ? "" }: [
    (pkgs.writeShellScriptBin name ''
      ${env}exec ${prio} ${pkgs.nono}/bin/nono run --profile agent -- ${bin} ${yolo} "$@"
    '')
    (pkgs.writeShellScriptBin "vanilla-${name}" ''
      ${env}exec ${prio} ${bin} "$@"
    '')
  ];
in
```

Die `env`/`yolo`-Trennung bildet das bestehende Verhalten exakt ab:
`vanilla-claude` behält `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, lässt aber
`--dangerously-skip-permissions` weg.

### Die vier Agents

```nix
home.packages = lib.concatLists [
  (mkAgent {
    name = "claude";
    bin = "${pkgs.claude-code}/bin/claude";
    env = "export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1\n";
    yolo = "--dangerously-skip-permissions";
  })
  (mkAgent {
    name = "opencode";
    bin = "${pkgs.opencode}/bin/opencode";
    # bewusst kein yolo-Flag (wie im bisherigen Wrapper)
  })
  (mkAgent {
    name = "codex";
    bin = "${pkgs.codex}/bin/codex";
    yolo = "<codex-yolo-flag — bei Umsetzung gegen --help verifizieren>";
  })
  (mkAgent {
    name = "pi";
    bin = "${pkgs.pi-coding-agent}/bin/pi";
    yolo = "<pi-yolo-flag — bei Umsetzung gegen --help verifizieren>";
  })
];
```

Binary-Namen verifiziert via `meta.mainProgram`: `codex` → `codex`,
`pi-coding-agent` → `pi`, `opencode` → `opencode`. Die exakten yolo-Flags für
`codex` und `pi` werden bei der Umsetzung gegen das `--help` der realisierten
Binaries bestätigt (codex vermutlich `--dangerously-bypass-approvals-and-sandbox`).

### nono-Profil-Relocation

1. Rohe Datei verbatim kopieren (Shell, nicht Copy-Paste):
   `cp ~/.config/nono/profiles/claude.json home/config/nono/profiles/agent.json`.
2. In der Repo-Kopie nur `meta.name` von `"claude"` auf `"agent"` ändern. Der
   restliche Inhalt bleibt identisch (er ist bereits agent-generisch:
   `"description": "general AI agent sandbox"`).
3. Out-of-store-Symlink in `ai-agents.nix`:
   ```nix
   home.file.".config/nono/profiles/agent.json".source =
     config.lib.file.mkOutOfStoreSymlink "${repoDir}/home/config/nono/profiles/agent.json";
   ```
4. Alte `~/.config/nono/profiles/claude.json` wird verwaist (anderer Dateiname →
   kein HM-Clobber-Konflikt). Manuelles Löschen durch den User nach erfolgreichem
   Switch.

## Datenfluss

`claude`/`opencode`/`codex`/`pi` im PATH → `writeShellScriptBin`-Wrapper →
`ionice`+`nice` → `nono run --profile agent` (lädt
`~/.config/nono/profiles/agent.json`, Symlink ins Repo) → echtes Agent-Binary mit
yolo-Flag im Sandbox-Namespace. `vanilla-*` überspringt nono.

Die Shell-Aliase in `shell-core.nix` (`opencode`, `oc`, `c`) lösen weiterhin gegen
den PATH-Befehl `opencode` auf — unverändert funktionsfähig.

## Fehlerbehandlung / Randfälle

- **PATH-Kollision**: `claude-code`, `opencode`, `codex`, `pi-coding-agent` dürfen
  NICHT zusätzlich in der reinen Paketliste stehen, sonst doppelte Binaries im
  PATH. Aktuell sind sie es nicht — beim Hinzufügen von codex/pi darauf achten,
  sie nur via `mkAgent` einzubinden.
- **Profil-Listing-Sperre**: Das beobachtete "Permission denied" beim Listen von
  `~/.config/nono` ist ein Artefakt der laufenden nono-Sandbox (Profil erlaubt
  `profiles/` lesen, nicht den Parent) — kein echtes Dateisystem-Problem. HM legt
  einzelne Datei-Symlinks in bestehenden Verzeichnissen problemlos an.
- **Symlink-Ziel im Sandbox**: Das Profil gewährt Read auf
  `$HOME/.config/nono/profiles`. nono lädt das Profil *vor* dem Sandboxing, daher
  ist der Symlink ins Repo unkritisch (Agents lesen Profile nicht zur Laufzeit).

## Verifikationsplan

1. `nixos-rebuild build --flake .` (ohne Aktivierung) auf der aktiven Spezialisierung
   → Syntax/Eval-Korrektheit.
2. `nono profile validate ~/.config/nono/profiles/agent.json` nach dem Switch
   (User-Aktion) → Profil bleibt valide.
3. `nono profile list` zeigt `agent` als User-Profil.
4. `claude`, `opencode`, `codex`, `pi` starten und laufen sandboxed; `vanilla-*`
   existieren und überspringen nono.
5. `realpath ~/.config/nono/profiles/agent.json` zeigt auf die Repo-Datei
   (out-of-store).

## Out of Scope

- Keine Änderung am Profil-Inhalt außer `meta.name`.
- Keine eigenen Profile pro Agent (geteiltes `agent`-Profil per Entscheidung).
- Keine Migration/Verwaltung des restlichen `~/.config/nono`-Verzeichnisses durch HM.
