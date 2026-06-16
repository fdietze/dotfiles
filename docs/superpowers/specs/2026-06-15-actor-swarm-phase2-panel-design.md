# Actor-Swarm Phase 2 — Swarm-Panel UI Design

## REVISIONEN AUS DER IMPLEMENTIERUNG (maßgeblich — überschreibt Abweichendes unten)

Während der Umsetzung in der echten pi-TUI zeigte sich, dass der ursprüngliche
Overlay-Entwurf nicht tragfähig war. Der tatsächlich umgesetzte und live
bestätigte Stand:

- **Kein Overlay.** `ctx.ui.custom(..., { overlay: true })` fror die TUI in der
  Praxis ein (auch awaited, auch mit Focusable-Klasse). Stattdessen:
  - **Persistentes Roster** über `ctx.ui.setWidget("swarm-roster", lines)` —
    immer sichtbar über dem Editor, live aktualisiert (plan-mode-Muster).
  - **Interaktion** über einen **Vollbild-Takeover** `ctx.ui.custom(factory)`
    **ohne** `overlay` (question.ts-Muster), geöffnet per **`/swarm`-Command**;
    `Esc` schließt. Der Takeover ersetzt den Editor-Bereich, solange er offen ist.
- **Kein `Ctrl+Q`-Shortcut.** Aktivierung per `/swarm`-Command (Wunsch des
  Nutzers; Shortcut entfiel mit dem Overlay).
- **ctx niemals cachen.** Ein gehaltener `ctx`/`ctx.ui` crasht pi nach
  Turn/Reload mit „stale ctx". Lösung: nur **Werte** cachen (z.B. die
  Kontext-Usage der `user`-Zeile), aufgefrischt aus jedem frischen Handler-ctx;
  UI-Aufrufe defensiv (`try/catch`).
- **Transcript zunächst als schlichter Text** (role + Inhalt) statt der
  Original-Message-Components: `ToolExecutionComponent` ist zu stark an die
  InteractiveMode gekoppelt (braucht `ui`/`cwd`/`toolDefinition`); ein Upgrade
  auf `User-/AssistantMessageComponent` für die Textanteile bleibt optional/additiv.
- Tastenbelegung im Takeover wie geplant: `↑/↓` Actor, Tippen→Chatbox,
  `Enter` sendet via `engine.route("user", gewählt, text)`, `PgUp/PgDn` scrollt,
  `Esc` schließt.

Die folgenden Abschnitte beschreiben den ursprünglichen Entwurf und sind, wo sie
Overlay/`Ctrl+Q`/Komponenten-Reuse behaupten, durch die obigen Revisionen ersetzt.


## Ziel

Ein tmux-artiges Panel, mit dem man die Actors des Swarms (Phase 1) überblickt und
mit jedem direkt interagiert, während alle weiterlaufen. Aufbauend auf der
Phase-1-Engine (`docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md`);
**reine UI-Schicht** — Routing/Caps/Halt/Spawn bleiben unverändert.

## Verhalten (vom Nutzer festgelegt)

- Ein **permanentes Panel oben**, das **alle Actors** listet. Minimal: **Name ·
  wie viel Kontext · aktiv/idle**.
- Hat das Panel **Fokus**, wechselt man mit **Pfeiltasten** den Actor und sieht
  dessen **Transcript live**.
- Die Transcript-Ansicht hat eine **Chatbox**, um Nachrichten an den Actor zu
  schicken.
- Fokus an/aus über **`Ctrl+Q`**. Keine Alt-Tasten.
- Strikt minimal: **keine** Unread-/Attention-Marker.

## Architektur

Ein **permanentes Overlay** via `ctx.ui.custom(factory, { overlay: true,
overlayOptions: { anchor: "top", ... } })`, einmalig bei `session_start` erzeugt
und dauerhaft sichtbar. Zwei Render-Zustände abhängig vom Fokus:

- **Unfokussiert (immer sichtbar):** kompakte Liste `Name · Kontext · aktiv/idle`.
- **Fokussiert:** Liste (mit Cursor) + Live-Transcript des gewählten Actors +
  Chatbox.

Fokus wird über einen registrierten Shortcut umgeschaltet
(`pi.registerShortcut("ctrl+q", ...)` → `handle.focus()` / `handle.unfocus()`).
Ein fokussiertes sichtbares Overlay besitzt die Eingabe; `Esc`/erneutes `Ctrl+Q`
gibt sie an den Haupt-Editor zurück (`handle.unfocus()`).

Neue Datei `panel.ts` (Overlay-Component + Verdrahtung). Pure, testbare Logik
(Roster-Zeilen-Formatierung, Selektions-Navigation, Scroll-Offset,
Chatbox→route-Mapping) in `panel-logic.ts` ausgelagert.

## Wiederverwendung der Original-pi-UI (verifiziert)

pi exportiert genau die Komponenten des Haupt-Chats — kein Neuerfinden, volle
visuelle Parität:

| Teil | Komponente (Export) | Quelle |
|------|---------------------|--------|
| Chatbox | `Editor` | `@earendil-works/pi-tui` |
| Transcript-Nachrichten | `UserMessageComponent`, `AssistantMessageComponent`, `ToolExecutionComponent`, `BashExecutionComponent` | `@earendil-works/pi-coding-agent` |
| Live-Streaming | `AssistantMessageComponent.updateContent(message)` | dito |
| Roster-Liste | `SelectList` (eingebaute `↑/↓`-Navigation) | `@earendil-works/pi-tui` |
| Markdown/Text | `Markdown`, `Text`, `Container`, `Box` | `@earendil-works/pi-tui` |

Transcript-Aufbau: `session.messages` (`AgentMessage[]`) → pro Nachricht die
passende Component instanziieren und in einen `Container` stapeln; bei
`message_update` die streamende `AssistantMessageComponent` per `updateContent`
aktualisieren.

**Nicht als fertige Einheit exportiert:** der Scroll-Viewport (Umbruch der
gestapelten Nachrichten, `PgUp/PgDn`). Den komponieren wir selbst als Offset über
den `Container` (`panel-logic.ts` berechnet den Offset, testbar).

## Engine-Erweiterung (klein)

Das Panel braucht pro Actor mehr als den Phase-1-`ActorHandle`
(`deliver/abort/isStreaming`): Transcript, Kontext-Usage und Live-Events. Daher
bekommt `ActorRecord` ein optionales `view`:

```ts
interface ActorView {
	getMessages(): AgentMessage[];
	getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined;
	subscribe(listener: (e: { type: string }) => void): () => void;
}
```

- **Hintergrund-Actors:** `view` aus ihrer `AgentSession`
  (`session.messages`, `session.getContextUsage()`, `session.subscribe()`).
- **`user`:** eingeschränkte View — Kontext-Usage best-effort über die
  Extension-API (falls verfügbar, sonst `—`); **kein** eigenes Transcript.

Die Engine bleibt sonst unverändert; `view` ist rein additiv und für Phase-1-Pfade
irrelevant.

## Tastenbelegung (im fokussierten Zustand)

| Taste | Aktion |
|-------|--------|
| `Ctrl+Q` | Fokus an/aus (global, via `registerShortcut`) |
| `↑` / `↓` | Actor in der Liste wählen (Transcript wechselt live mit) |
| *(tippen)* | landet in der Chatbox (`Editor`) |
| `Enter` | Chatbox-Inhalt an gewählten Actor: `engine.route("user", gewählt, text)` |
| `PgUp` / `PgDn` | Transcript scrollen (selbst berechneter Offset) |
| `Esc` | Fokus zurück an den Haupt-Chat (`handle.unfocus()`) |

## Sonderfall `user`-Zeile

`user` steht in der Liste (Kontext/aktiv wie andere). Wird `user` gewählt, zeigt
das Transcript-Feld nur den Hinweis *„= Haupt-Chat unten"* statt einer Kopie — der
echte `user`-Transcript gehört pi und läuft darunter weiter. Senden an `user` aus
der Chatbox bleibt möglich (landet im Haupt-Chat + triggert Antwort, wie Phase 1).

## Live-Updates

Das Panel abonniert die Events aller Actor-Sessions (`view.subscribe`) und ruft
**gedrosselt** `tui.requestRender()`. So bleiben Kontext-/Aktiv-Status der Liste
und das sichtbare Transcript live. Beim Actor-Wechsel wird auf die `view` des neu
gewählten Actors umgehängt.

## Datenfluss

1. `Ctrl+Q` → `handle.focus()`; Panel rendert expandiert, `Editor` bekommt Eingabe.
2. `↑/↓` → Selektion ändert sich; Panel hängt Transcript auf `view` des gewählten
   Actors um (rendert `session.messages`, abonniert Live-Events).
3. Tippen + `Enter` → `engine.route("user", selected, text)` (Phase-1-Pfad:
   `view`/Handle stellt via `sendUserMessage(..., followUp)` zu, weckt idle Actor).
4. Actor-Antwort streamt → `message_update` → `updateContent` → Live im Transcript.
5. `Esc`/`Ctrl+Q` → `handle.unfocus()`; Panel kollabiert zur kompakten Liste,
   Eingabe zurück am Haupt-Editor.

## Testing

Pure Logik in `panel-logic.ts` mit `node:test`:
- Roster-Zeilen-Formatierung (Name, `tokens/contextWindow · percent`, aktiv/idle),
  inkl. `tokens: null` (→ `—`).
- Selektions-Navigation (`↑/↓` mit Clamp an den Rändern, leere/teilweise Liste).
- Scroll-Offset (`PgUp/PgDn`, Clamp, kürzer/länger als Viewport).
- Chatbox→route-Mapping (gewählter Actor + Text → `route`-Argumente; leerer Text =
  kein Versand).

Der Overlay-Component selbst (TUI-Rendering, Fokus, Tasten) wird manuell
verifiziert.

## Feasibility (Quellcode-Verifikation, pi 0.79.1)

- `ctx.ui.custom(..., { overlay: true })` rendert persistente, fokussierbare
  Overlays; `handle.focus()/unfocus()` steuern den Eingabe-Besitz, Overlay bleibt
  sichtbar.
- `pi.registerShortcut("ctrl+q", ...)` ist verfügbar; `ctrl+q` ist nicht belegt
  (frei laut `keybindings.md`; pi läuft im Raw-Mode → kein XON/XOFF-Konflikt).
- `AgentSession` exportiert `messages`, `getContextUsage()` (`{ tokens,
  contextWindow, percent }`), `isStreaming`, `subscribe()`.
- Message-Komponenten + `Editor` + `SelectList` sind exportiert und entsprechen
  dem Haupt-Chat (`AssistantMessageComponent.updateContent` für Streaming).

## Bewusst nicht in Phase 2 (YAGNI)

- Attention/Unread-Marker (Nutzer wählte „strikt minimal").
- Actor aus dem Panel beenden/killen.
- Picker-/Cycle-Hotkeys, Maus-Unterstützung, Such-/Filterfunktion.
- Spiegelung des `user`-Transcripts ins Panel.
- Disk-Persistenz, Settings-Binding (erbt Phase-1-Stand).
