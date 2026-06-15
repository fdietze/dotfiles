# Actor-Swarm pi-Extension — Design (Phase 1)

## Ziel

Eine pi-Extension, die Agents als **Actors** behandelt: benannte Agent-Sessions,
die sich gegenseitig **fire-and-forget** Nachrichten per Tool-Call schicken
können. Agents können zur Laufzeit neue Agents erzeugen. Der Mensch (die
Vordergrund-TUI) ist selbst ein adressierbarer Actor namens `user`.

Dieses Dokument beschreibt **Phase 1**. Das tmux-artige Umschalt-UI ist
ausdrücklich Phase 2 (siehe "Bewusst nicht in Phase 1").

## Kontext und Begründung der Kern-Entscheidung

pi hat keine eingebauten Sub-Agents (`docs/usage.md`). Das offizielle
`subagent`-Beispiel startet pro Aufgabe einen eigenen `pi`-Subprozess und
kommuniziert per JSON-über-stdout — einseitig und einmalig (fire-and-collect),
keine gegenseitigen Nachrichten.

Für gegenseitige fire-and-forget-Kommunikation wäre bei getrennten Prozessen ein
Transport über Prozessgrenzen nötig (Sockets/IPC/Dateisystem). Das nono-Agent-
Profil blockiert aber `ipc_mode` und Unix-Sockets standardmäßig.

**Entscheidung: alle Actors in *einem* Prozess.** Über das pi-SDK können beliebig
viele `AgentSession`-Instanzen in einem Node-Prozess gehalten werden. Jede Session
ist bereits ein Actor mit isoliertem Kontext, eigener History und eigenem Modell.
Vorteile:

- Fire-and-forget = ein direkter In-Memory-Aufruf (`session.sendMessage(...)`,
  nicht awaiten). Kein Transport, kein Serialisieren.
- Umgeht die Sandbox-Beschränkung komplett: keine IPC/Sockets/Subprozesse →
  **keine Änderung am nono-Profil nötig**.
- Mailbox-Semantik ist eingebaut: `sendMessage` mit `deliverAs` +
  `triggerTurn` reiht bei beschäftigten Actors ein und weckt idle Actors.
- Echte Nebenläufigkeit für den I/O-lastigen Teil (LLM-Requests, Tool-Calls)
  über den Event-Loop.

Preis: pi's TUI rendert genau eine Vordergrund-Session; Hintergrund-Actors laufen
headless. Beobachtbarkeit/Steuerung muss die Extension selbst liefern. Phase 1
löst das read-only (Feed + Status); volle Interaktion ist Phase 2.

Wichtig: pi's eingebauter `runtime.switchSession()`/`newSession()` ruft
`teardownCurrent → session.dispose()` auf, zerstört also die vorherige Session.
Deshalb dürfen Actors **nicht** über die Runtime verwaltet werden, sondern als
eigenständige, von der Extension gehaltene `AgentSession`-Objekte.

## Spike-Erkenntnisse (Quellcode-Verifikation, pi 0.79.1)

Vor dem Plan wurden die zwei riskantesten Unbekannten gegen den pi-Quellcode
geprüft:

- **Mehrere lebende Sessions in einem Prozess: tragfähig.** `core/agent-session`
  und `agent-session-runtime` enthalten keine Prozess-Globals für
  Terminal/stdin/Signale. Die einzige globale stdout-Übernahme (`takeOverStdout`
  in `output-guard`) sitzt in der Run-Mode-Schicht (interactive/rpc/print), nicht
  in `AgentSession`. Headless erzeugte Hintergrund-Sessions fassen das Terminal
  also nicht an; nur der eine Vordergrund-Run-Mode besitzt es. Deckt sich exakt
  mit dieser Architektur.
- **Tastengetriebener globaler Not-Aus: nicht baubar.** In pi ist `ctrl+c`
  nicht Abort, sondern `app.clear` (Editor leeren); der Interrupt liegt auf
  `escape` und bricht nur den Vordergrund-Turn ab. Extensions können globale
  `app.*`-Keybindings nicht überschreiben (`KeybindingsManager` ist nur in
  eigene `ctx.ui.custom()`-Components injiziert). Folge: Der Not-Aus wird als
  `/halt`-**Command** umgesetzt (Commands sind voll unterstützt), nicht als
  Tastenkürzel.

## Architektur

Ein Prozess. Die Extension hält eine **In-Memory-Registry** `name → AgentSession`.
Die normale Vordergrund-TUI ist der Actor `user`. Alle anderen Actors laufen
headless im selben Prozess.

- Actors werden **lazy** beim ersten `spawn_agent` erzeugt (via SDK
  `createAgentSession`), mit gleicher cwd / Tools / Sandbox wie der Hauptprozess.
- Default-Modell eines gespawnten Actors = das Modell des Spawners (ererbt),
  überschreibbar.
- Persistenz: **in-memory only** in Phase 1. Actors sterben mit dem Prozess.
  (Disk-Persistenz ist potenzielle Phase 2.)

## Komponenten / Dateien

```
home/.../pi-extensions/actor-swarm/
  index.ts        # Entry: registriert Tools + Commands, instanziiert Engine
  engine.ts       # Registry, Spawn, Routing, Caps, Halt-State, Turn-Budget
  feed.ts         # In-Memory Activity-Log + Rendering (/actors, /feed)
```

Deployment nach `~/.pi/agent/extensions/actor-swarm/`, Nix-managed in den
dotfiles.

## Tools (für jeden Actor inkl. `user`)

- **`spawn_agent({ name, role, model?, tools? })`**
  Erzeugt einen Actor. `role` = Systemprompt (inline). `model` default = ererbt
  vom Spawner. `tools` default = Standard-Toolset.
  Rückgabe (Ack): `spawned 'coder'` bzw. `'coder' already exists`.

- **`send_message({ to, content })`**
  Fire-and-forget. Stellt zu via `zielSession.sendMessage` mit
  `deliverAs: "followUp"` + `triggerTurn: true`. Der Empfänger sieht den Inhalt
  als User-Nachricht im Format `[message from <sender>]: <content>`.
  Rückgabe sofort: `queued to 'coder' (was idle → woken | busy → queued)`.
  Existiert `to` nicht → Fehler (kein Auto-Spawn — hält die Caps ehrlich).

- **`list_agents()`**
  Roster + Status, damit ein Actor weiß, wen er adressieren kann.

Jedem Actor wird in den Systemprompt injiziert: sein eigener Name + kurze
Erklärung der drei Tools.

## Datenfluss einer Nachricht

1. `send_message` aufgerufen.
2. Engine prüft Halt-State und Caps (siehe Sicherheit).
3. Engine schreibt einen Activity-Log-Eintrag.
4. Engine ruft
   `zielSession.sendMessage({ role: "user", content: "[from X] …",
   deliverAs: "followUp", triggerTurn: true })`.
5. Tool kehrt sofort mit Ack zurück (kein Warten auf den Empfänger-Turn).

Jede Nachricht trägt intern eine **Herkunfts-Kette** (z.B. `user→planner→coder`)
als Metadatum für Log/Debugging und zur Tiefenberechnung. Die Kette wird nur
sichtbar gemacht, nicht als Routing-Policy erzwungen.

## Zustellsemantik

Reine Mailbox-Semantik (`followUp`): eine eingehende Nachricht unterbricht einen
laufenden Turn **nie**, sondern wird zugestellt, sobald der Actor seinen
aktuellen Turn komplett beendet hat. Idle Actors werden sofort geweckt
(`triggerTurn`). Ein per-Nachricht-`priority`/`steer` ist Phase 2.

## Sicherheit (harte Caps + Not-Aus)

Konfigurierbar über Extension-Settings, mit Defaults:

- `maxActors` (Default 8): `spawn_agent` schlägt bei Überschreitung fehl.
- `maxSpawnDepth` (Default 3): Spawn-Tiefe aus der Herkunfts-Kette; tiefere
  Spawns werden abgelehnt.
- `turnBudget` (Default 100): globaler Zähler über **alle** Actors. Bei 0 werden
  neue Turns abgelehnt.

Not-Aus (`/halt` Command — kein Tastenkürzel, siehe Spike-Erkenntnisse):

- `/halt` setzt `frozen = true`: keine neuen Sends/Spawns/Turns. Jeder Actor
  prüft im `turn_start`-Hook das `frozen`-Flag und ruft `session.abort()` auf
  sich selbst auf, damit `/halt` auch laufende Turns stoppt.
- `/resume` hebt `frozen` auf und setzt das Turn-Budget zurück.
- pi's eingebautes `escape` bleibt unangetastet: es bricht weiterhin nur den
  Vordergrund-Turn (`user`) ab, nicht den Schwarm.

Die Herkunfts-Kette wird mitgetragen (fast gratis), aber nur Caps + Not-Aus
werden erzwungen. Loop-Erkennung als eigene Policy ist Phase 2.

## Beobachtbarkeit (read-only, Phase 1)

- **Footer-Status** via `pi.setStatus`:
  `swarm: 4 actors · 1 running · budget 73/100`.
- **`/actors`**: Snapshot — Name, Modell, Status (idle/running), letzte
  Aktivität, Anzahl Turns.
- **`/feed`**: Overlay (`ctx.ui.custom({ overlay: true })`) mit scrollbarem
  Live-Log aller Routing- und Turn-Events. Read-only.

## Testing

- Engine pur (Registry, Caps, Halt, Turn-Budget, Routing-Entscheidung) gegen
  **Fake-Sessions** (Stub mit `sendMessage` / `abort` / Status) — schnelle
  Unit-Tests ohne LLM-Calls. TDD-fähig.
- Caps-Grenzfälle als Tabellentests: `maxActors + 1`, Tiefe + 1, Budget = 0,
  Send an nicht-existenten Actor, Spawn doppelten Namens.
- Halt/Resume: Send/Spawn/Turn im `frozen`-Zustand abgelehnt; `abort` auf
  laufende Sessions aufgerufen.
- Manueller Smoke-Test mit echtem Modell zum Schluss.

## Bewusst nicht in Phase 1 (YAGNI)

- tmux-artiges Umschalt-UI (volle Interaktion mit Hintergrund-Actors) — Phase 2.
- `kill_agent` / Idle-Timeout für einzelne Actors.
- Disk-Persistenz von Actor-Sessions.
- Loop-Erkennung als eigene Drossel-Policy.
- Confirm-Gate (Mensch-im-Kreis) vor Spawn/Wecken.
- Per-Nachricht-`priority`/`steer`.

Alle Punkte sind additiv und brechen das Phase-1-Design nicht.
