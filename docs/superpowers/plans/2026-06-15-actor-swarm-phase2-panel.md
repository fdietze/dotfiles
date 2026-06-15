# Actor-Swarm Phase 2 — Swarm-Panel Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. Pure-logic tasks are TDD with `node:test`. The TUI component cannot be auto-tested from inside the agent sandbox (pi is nono-wrapped; nono-in-nono fails), so component tasks end with a **manual verification** the user runs in their pi session after `nrs` + `/reload`. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ein permanentes, tmux-artiges Panel oben, das alle Actors listet (Name · Kontext · aktiv/idle). Mit `Ctrl+Q` bekommt es Fokus; `↑/↓` wählt einen Actor und zeigt dessen Transcript live; eine Chatbox schickt Nachrichten an den gewählten Actor. Reine UI-Schicht über der Phase-1-Engine.

**Spec:** `docs/superpowers/specs/2026-06-15-actor-swarm-phase2-panel-design.md`

**Architecture:** Persistentes Overlay via `ctx.ui.custom(factory, { overlay: true, overlayOptions, onHandle })`, einmal bei `session_start` erzeugt; Handle gecacht. `pi.registerShortcut("ctrl+q", ...)` toggelt `handle.focus()/unfocus()`. Der Panel-Component (Component+Focusable) komponiert: hand-gerollte Roster-Zeilen (pure Logik in `panel-logic.ts`) + Transcript-`Container` aus **wiederverwendeten** `UserMessageComponent`/`AssistantMessageComponent` (Tool-Calls minimal als Einzeiler) + `Editor` als Chatbox. Pro Actor liefert eine neue `ActorView` (Engine-Erweiterung) `messages`/`contextUsage`/`subscribe`.

**Tech Stack:** TypeScript (jiti), `@earendil-works/pi-tui` (`Editor`, `Container`, `Text`, `matchesKey`, `Key`), `@earendil-works/pi-coding-agent` (`UserMessageComponent`, `AssistantMessageComponent`), `node:test` für pure Logik.

---

## Verified API facts (pi 0.79.1)

- Overlay: `ctx.ui.custom(factory, { overlay: true, overlayOptions: { anchor, width, maxHeight, ... }, onHandle })`. Handle: `focus()`, `unfocus()`, `setHidden()`, `requestRender()`, `close()`. Persistent = Promise nicht awaiten, `done` erst bei Shutdown.
- Component: `render(width): string[]`, `handleInput?(data)`, `invalidate()`. `Focusable`: `focused: boolean` (Container an Editor-Child propagieren).
- Keys: `matchesKey(data, Key.up | Key.down | Key.pageUp | Key.pageDown | Key.enter | Key.escape)`.
- Shortcut: `pi.registerShortcut("ctrl+q", { handler })`. `ctrl+q` ist frei.
- Session-View: `session.messages` (`AgentMessage[]`), `session.getContextUsage()` (`{ tokens, contextWindow, percent }`), `session.isStreaming`, `session.subscribe(listener)`.
- `user`-Kontext: `ctx.getContextUsage()` (ExtensionContext).
- Reuse: `UserMessageComponent(text, markdownTheme?)`, `AssistantMessageComponent(message?, hideThinkingBlock?, markdownTheme?)` (+ `updateContent`). `ToolExecutionComponent` ist zu stark an InteractiveMode gekoppelt → **nicht** wiederverwendet; Tool-Calls als Einzeiler `⚙ <name>`.

---

## File Structure

```
.../actor-swarm/
  engine.ts        # + optional `view?: ActorView` auf ActorRecord; ActorView-Typ
  swarm.ts         # background-Actor: view aus der Session befüllen
  panel-logic.ts   # NEU: pure Helfer (Roster-Format, Selektion, Scroll, Chatbox→route)
  panel-logic.test.ts # NEU
  panel.ts         # NEU: SwarmPanel-Component (reuse von Editor + Message-Components)
  index.ts         # + view für user (ctx.getContextUsage), Overlay + ctrl+q registrieren
```

---

## Task 1: Spike — persistentes Overlay + Ctrl+Q-Fokus (manuell)

Ziel: die riskanteste Mechanik (persistentes Overlay, das per `Ctrl+Q` Fokus bekommt/abgibt) isoliert bestätigen, **bevor** das volle Panel gebaut wird.

**Files:** Modify `index.ts` (temporärer Spike-Block, in Task 4 ersetzt).

- [ ] **Step 1: Minimal-Overlay + Shortcut einbauen**

In `index.ts` (am Ende des Default-Exports) temporär:

```ts
	// SPIKE (Task 1): wird in Task 4 durch das echte Panel ersetzt.
	let panelHandle: { focus(): void; unfocus(): void; requestRender(): void; close(): void } | undefined;
	let panelFocused = false;
	const spikeComponent = {
		focused: false,
		render(width: number): string[] {
			const tag = this.focused ? "[FOCUSED]" : "[idle]";
			return [` swarm spike ${tag} — Ctrl+Q toggelt, Esc gibt Fokus zurück `.slice(0, width)];
		},
		handleInput(data: string) {
			// nur zum Test: Esc gibt Fokus zurück
		},
		invalidate() {},
	};
	pi.on("session_start", (_e, ctx) => {
		if (panelHandle) return;
		ctx.ui.custom(
			() => spikeComponent,
			{
				overlay: true,
				overlayOptions: { anchor: "top-center", width: "60%", margin: { top: 1, right: 0, bottom: 0, left: 0 } },
				onHandle: (h) => {
					panelHandle = h;
				},
			},
		);
	});
	pi.registerShortcut("ctrl+q", {
		description: "Toggle swarm panel focus",
		handler: async () => {
			if (!panelHandle) return;
			panelFocused = !panelFocused;
			spikeComponent.focused = panelFocused;
			if (panelFocused) panelHandle.focus();
			else panelHandle.unfocus();
			panelHandle.requestRender();
		},
	});
```

- [ ] **Step 2: `node --check`**

Run: `cd .../actor-swarm && node --check index.ts` → exit 0.

- [ ] **Step 3: Manuelle Verifikation (Nutzer)**

`nrs` + `/reload`, dann:
- Ein Overlay-Streifen oben erscheint dauerhaft (`[idle]`).
- `Ctrl+Q` → wechselt zu `[FOCUSED]`; Tippen geht nicht mehr in den Haupt-Editor.
- `Ctrl+Q` erneut → zurück zu `[idle]`, Haupt-Editor bekommt Eingabe.

**Gate:** Funktioniert das nicht wie erwartet (Overlay nicht persistent, Fokus toggelt nicht, `onHandle` liefert kein Handle), hier stoppen und die Overlay-/Handle-API anhand `examples/extensions/overlay-qa-tests.ts` korrigieren, bevor es weitergeht.

- [ ] **Step 4: Commit (Spike, wird ersetzt)**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/index.ts
git commit -m "spike(actor-swarm): persistent overlay + ctrl+q focus toggle"
```

---

## Task 2: Engine — optionale ActorView

**Files:** Modify `engine.ts`; Test `engine.test.ts` (append).

- [ ] **Step 1: Failing test**

Append to `engine.test.ts`:

```ts
test("addActor preserves optional view", () => {
	const e = new Engine(caps);
	const msgs: unknown[] = [{ role: "user", content: "hi" }];
	const view = {
		getMessages: () => msgs,
		getContextUsage: () => ({ tokens: 100, contextWindow: 200000, percent: 0.05 }),
		subscribe: () => () => {},
	};
	e.addActor({ ...userRecord(), name: "a", depth: 1, view });
	assert.equal(e.get("a")?.view?.getMessages().length, 1);
	assert.equal(e.get("a")?.view?.getContextUsage()?.contextWindow, 200000);
});
```

- [ ] **Step 2: Run → fails** (`view` not on type / not stored). `node --test engine.test.ts`.

- [ ] **Step 3: Implement**

In `engine.ts`, add the type and field:

```ts
export interface ActorView {
	getMessages(): unknown[];
	getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined;
	subscribe(listener: (e: { type: string }) => void): () => void;
}
```

Add to `ActorRecord`:

```ts
	/** Optional: Live-Sicht auf Transcript/Kontext/Events (für das Panel). */
	view?: ActorView;
```

(`addActor` speichert das ganze Record-Objekt bereits via `this.actors.set(rec.name, rec)` — keine weitere Änderung nötig.)

- [ ] **Step 4: Run → passes.** `node --test` (full suite green).

- [ ] **Step 5: Commit**

```bash
git add .../actor-swarm/engine.ts .../actor-swarm/engine.test.ts
git commit -m "feat(actor-swarm): optional ActorView on records for the panel"
```

---

## Task 3: panel-logic.ts — pure Helfer (TDD)

**Files:** Create `panel-logic.ts`, `panel-logic.test.ts`.

- [ ] **Step 1: Failing tests**

Create `panel-logic.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { formatContext, formatRosterRow, moveSelection, clampScroll, chatboxToRoute } from "./panel-logic.ts";

test("formatContext renders tokens/window/percent, and dash when unknown", () => {
	assert.match(formatContext({ tokens: 12000, contextWindow: 200000, percent: 0.06 }), /12k\/200k.*6%/);
	assert.equal(formatContext({ tokens: null, contextWindow: 200000, percent: null }), "—");
	assert.equal(formatContext(undefined), "—");
});

test("formatRosterRow shows cursor, name, context, status", () => {
	const row = formatRosterRow({ name: "echo", context: "3k/200k · 2%", active: true }, true, 40);
	assert.match(row, /▸/);
	assert.match(row, /echo/);
	assert.match(row, /active/);
	assert.ok(row.length <= 40);
});

test("moveSelection clamps at both ends", () => {
	assert.equal(moveSelection(0, -1, 3), 0);
	assert.equal(moveSelection(0, 1, 3), 1);
	assert.equal(moveSelection(2, 1, 3), 2);
	assert.equal(moveSelection(0, 1, 0), 0); // empty
});

test("clampScroll keeps offset within [0, max]", () => {
	assert.equal(clampScroll(5, 100, 10), 5);
	assert.equal(clampScroll(-3, 100, 10), 0);
	assert.equal(clampScroll(95, 100, 10), 90); // max = total - viewport
	assert.equal(clampScroll(5, 8, 10), 0); // content shorter than viewport
});

test("chatboxToRoute maps selected actor + text, rejects empty/self", () => {
	assert.deepEqual(chatboxToRoute("echo", "ping"), { to: "echo", content: "ping" });
	assert.equal(chatboxToRoute("echo", "   "), null);
	assert.equal(chatboxToRoute(undefined, "ping"), null);
});
```

- [ ] **Step 2: Run → fails.** `node --test panel-logic.test.ts`.

- [ ] **Step 3: Implement**

Create `panel-logic.ts`:

```ts
/** Pure Helfer fürs Swarm-Panel — keine pi/TUI-Abhängigkeit, voll testbar. */

export interface ContextUsageLike {
	tokens: number | null;
	contextWindow: number;
	percent: number | null;
}

const k = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}k` : `${n}`);

export function formatContext(u: ContextUsageLike | undefined): string {
	if (!u || u.tokens === null) return "—";
	const pct = u.percent === null ? "" : ` · ${Math.round(u.percent * 100)}%`;
	return `${k(u.tokens)}/${k(u.contextWindow)}${pct}`;
}

export interface RosterEntry {
	name: string;
	context: string;
	active: boolean;
}

export function formatRosterRow(entry: RosterEntry, selected: boolean, width: number): string {
	const cursor = selected ? "▸ " : "  ";
	const status = entry.active ? "●active" : " idle";
	const line = `${cursor}${entry.name.padEnd(12)} ${entry.context.padEnd(16)} ${status}`;
	return line.length > width ? line.slice(0, width) : line;
}

export function moveSelection(current: number, delta: number, count: number): number {
	if (count <= 0) return 0;
	const next = current + delta;
	if (next < 0) return 0;
	if (next > count - 1) return count - 1;
	return next;
}

/** offset so dass [offset, offset+viewport) gültig bleibt; clamp auf [0, max]. */
export function clampScroll(offset: number, total: number, viewport: number): number {
	const max = Math.max(0, total - viewport);
	if (offset < 0) return 0;
	if (offset > max) return max;
	return offset;
}

export function chatboxToRoute(selected: string | undefined, text: string): { to: string; content: string } | null {
	if (!selected) return null;
	const content = text.trim();
	if (!content) return null;
	return { to: selected, content };
}
```

- [ ] **Step 4: Run → passes.** `node --test` (full suite green).

- [ ] **Step 5: Commit**

```bash
git add .../actor-swarm/panel-logic.ts .../actor-swarm/panel-logic.test.ts
git commit -m "feat(actor-swarm): pure panel-logic helpers (roster/selection/scroll/route)"
```

---

## Task 4: index.ts/swarm.ts — ActorView verdrahten, Spike durch echtes Panel ersetzen

**Files:** Modify `swarm.ts` (background view), `index.ts` (user view + Overlay/Shortcut auf echtes Panel zeigen).

- [ ] **Step 1: Background-View in swarm.ts**

In `swarm.ts`, `SessionLike` um die Read-APIs erweitern und beim `addActor` ein `view` setzen:

```ts
export interface SessionLike {
	sendUserMessage(text: string, options?: { deliverAs?: "steer" | "followUp" }): Promise<void> | void;
	abort(): Promise<void> | void;
	readonly isStreaming: boolean;
	subscribe(listener: (e: { type: string }) => void): () => void;
	readonly messages: unknown[];
	getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined;
}
```

Im `spawnActor` beim `engine.addActor({...})` ergänzen:

```ts
			view: {
				getMessages: () => session.messages,
				getContextUsage: () => session.getContextUsage(),
				subscribe: (l) => session.subscribe(l),
			},
```

- [ ] **Step 2: user-View in index.ts**

Im `session_start`-Handler, beim Anlegen des `user`-Records, `ctx` einfangen und eine View setzen (Transcript bewusst leer → Panel zeigt „= Haupt-Chat unten"):

```ts
		const ctxRef = ctx; // für getContextUsage
		// ... beim user-addActor:
		view: {
			getMessages: () => [], // user-Transcript = Haupt-Chat (nicht gespiegelt)
			getContextUsage: () => ctxRef.getContextUsage(),
			subscribe: () => () => {},
		},
```

- [ ] **Step 3: Spike-Block durch echtes Panel ersetzen**

Den Spike-Component aus Task 1 entfernen und durch `SwarmPanel` (Task 5) ersetzen:

```ts
	import { SwarmPanel } from "./panel.ts"; // oben bei den Imports
	// ...
	let panel: SwarmPanel | undefined;
	let panelHandle: { focus(): void; unfocus(): void; requestRender(): void; close(): void } | undefined;
	pi.on("session_start", (_e, ctx) => {
		if (panelHandle) return;
		panel = new SwarmPanel({
			engine,
			route: (to, content) => void engine.route("user", to, content),
			onUnfocus: () => {
				panelHandle?.unfocus();
				panelHandle?.requestRender();
			},
		});
		ctx.ui.custom((tui, theme, _kb, _done) => {
			panel!.attach(tui, theme);
			return panel!;
		}, {
			overlay: true,
			overlayOptions: { anchor: "top-center", width: "70%", maxHeight: "70%", margin: { top: 1, right: 0, bottom: 0, left: 0 } },
			onHandle: (h) => { panelHandle = h; },
		});
		// Engine-Events → Panel neu rendern (gedrosselt in Task 6).
		engine.subscribe(() => panelHandle?.requestRender());
	});
	pi.registerShortcut("ctrl+q", {
		description: "Toggle swarm panel focus",
		handler: async () => {
			if (!panel || !panelHandle) return;
			const nowFocused = panel.toggleFocus();
			if (nowFocused) panelHandle.focus();
			else panelHandle.unfocus();
			panelHandle.requestRender();
		},
	});
```

- [ ] **Step 4: `node --check` für index.ts und swarm.ts.** (Task 5 erstellt `panel.ts`; bis dahin schlägt der Import fehl — diesen Task gemeinsam mit Task 5 fertigstellen, dann prüfen.)

- [ ] **Step 5: Commit (zusammen mit Task 5).**

---

## Task 5: panel.ts — SwarmPanel-Component (reuse)

**Files:** Create `panel.ts`.

- [ ] **Step 1: Implement SwarmPanel**

`SwarmPanel` implementiert `Component` + `Focusable`. Zustände: `focused`. Hält `selectedIndex`, `scrollOffset`, eine `Editor`-Instanz (Chatbox), und baut das Transcript via Message-Components.

```ts
import { Container, Editor, type Focusable, Key, matchesKey, Text, truncateToWidth } from "@earendil-works/pi-tui";
import { AssistantMessageComponent, UserMessageComponent } from "@earendil-works/pi-coding-agent";
import type { Engine } from "./engine.ts";
import { clampScroll, formatContext, formatRosterRow, moveSelection } from "./panel-logic.ts";

interface SwarmPanelDeps {
	engine: Engine;
	route: (to: string, content: string) => void;
	onUnfocus: () => void;
}

export class SwarmPanel implements Focusable {
	focused = false;
	private selectedIndex = 0;
	private scrollOffset = 0;
	private editor = new Editor();
	private theme: unknown;
	private unsubView: (() => void) | undefined;

	constructor(private readonly deps: SwarmPanelDeps) {}

	attach(_tui: unknown, theme: unknown) {
		this.theme = theme;
	}

	toggleFocus(): boolean {
		this.focused = !this.focused;
		this.editor.focused = this.focused;
		if (this.focused) this.rebindView();
		return this.focused;
	}

	private actors() {
		return this.deps.engine.list();
	}

	private selectedName(): string | undefined {
		return this.actors()[this.selectedIndex]?.name;
	}

	/** Auf die View des aktuell gewählten Actors abonnieren (Live-Re-Render kommt aus index via engine.subscribe + hier). */
	private rebindView() {
		this.unsubView?.();
		const rec = this.actors()[this.selectedIndex];
		this.unsubView = rec?.view?.subscribe(() => {/* requestRender erfolgt über index onHandle */});
	}

	handleInput(data: string): void {
		if (matchesKey(data, Key.escape)) {
			this.focused = false;
			this.editor.focused = false;
			this.deps.onUnfocus();
			return;
		}
		if (matchesKey(data, Key.up)) {
			this.selectedIndex = moveSelection(this.selectedIndex, -1, this.actors().length);
			this.scrollOffset = 0;
			this.rebindView();
			return;
		}
		if (matchesKey(data, Key.down)) {
			this.selectedIndex = moveSelection(this.selectedIndex, 1, this.actors().length);
			this.scrollOffset = 0;
			this.rebindView();
			return;
		}
		if (matchesKey(data, Key.pageUp)) {
			this.scrollOffset -= 5;
			return;
		}
		if (matchesKey(data, Key.pageDown)) {
			this.scrollOffset += 5;
			return;
		}
		if (matchesKey(data, Key.enter)) {
			const to = this.selectedName();
			const text = this.editor.getText().trim();
			if (to && text) {
				this.deps.route(to, text);
				this.editor.setText("");
			}
			return;
		}
		this.editor.handleInput(data);
	}

	invalidate(): void {
		this.editor.invalidate?.();
	}

	render(width: number): string[] {
		const actors = this.actors();
		// 1) Roster (immer)
		const roster = actors.map((a, i) =>
			formatRosterRow(
				{ name: a.name, context: formatContext(a.view?.getContextUsage()), active: a.streaming },
				this.focused && i === this.selectedIndex,
				width,
			),
		);
		const lines: string[] = [truncateToWidth(" swarm ".padEnd(width, "─"), width), ...roster];
		if (!this.focused) return lines;

		// 2) Transcript des gewählten Actors (nur fokussiert)
		lines.push(truncateToWidth("─".repeat(width), width));
		const rec = actors[this.selectedIndex];
		const transcript = this.renderTranscript(rec, width);
		lines.push(...transcript);

		// 3) Chatbox
		lines.push(truncateToWidth("─".repeat(width), width));
		lines.push(...this.editor.render(width));
		lines.push(truncateToWidth(" Ctrl+Q/Esc: zurück · ↑/↓ Actor · PgUp/PgDn scroll ", width));
		return lines;
	}

	private renderTranscript(rec: ReturnType<Engine["list"]>[number] | undefined, width: number): string[] {
		if (!rec) return ["(no actor)"];
		if (rec.name === "user") return ["= Haupt-Chat unten ="];
		const messages = (rec.view?.getMessages() ?? []) as { role?: string; content?: unknown; text?: string }[];
		const container = new Container();
		for (const m of messages) {
			const comp = this.messageComponent(m);
			if (comp) container.addChild(comp);
		}
		const all = container.render(width);
		const viewport = 12;
		this.scrollOffset = clampScroll(this.scrollOffset, all.length, viewport);
		return all.slice(this.scrollOffset, this.scrollOffset + viewport);
	}

	/** Reuse der Original-Renderer für user/assistant; Tool-Calls minimal. */
	private messageComponent(m: { role?: string; content?: unknown; text?: string }) {
		const theme = this.theme as never;
		if (m.role === "user") return new UserMessageComponent(textOf(m), theme);
		if (m.role === "assistant") return new AssistantMessageComponent(m as never, false, theme);
		if (m.role === "tool") return new Text(`⚙ tool result`, 1, 0);
		return undefined;
	}
}

function textOf(m: { content?: unknown; text?: string }): string {
	if (typeof m.text === "string") return m.text;
	if (typeof m.content === "string") return m.content;
	if (Array.isArray(m.content)) {
		return m.content.map((p: { text?: string }) => p?.text ?? "").join("");
	}
	return "";
}
```

> **Implementation note:** Die exakte `AgentMessage`-Form (Felder `role`/`content`/tool-Discriminator) und die `AssistantMessageComponent`-Argumentform werden beim Bauen kurz an `session.messages` zur Laufzeit geprüft und `messageComponent`/`textOf` ggf. angepasst — die Logik ist bewusst in *einer* Funktion isoliert. `Editor`-Methoden (`getText`/`setText`/`render`/`handleInput`/`focused`) gegen `editor-component.d.ts` verifizieren.

- [ ] **Step 2: `node --check` für panel.ts, index.ts, swarm.ts.** Alle exit 0.

- [ ] **Step 3: Full pure suite green.** `node --test` (engine + feed + swarm + panel-logic).

- [ ] **Step 4: Commit (Task 4 + 5 zusammen)**

```bash
git add .../actor-swarm/panel.ts .../actor-swarm/index.ts .../actor-swarm/swarm.ts
git commit -m "feat(actor-swarm): SwarmPanel component (roster + reused transcript + chatbox)"
```

---

## Task 6: Live-Updates drosseln + Streaming

**Files:** Modify `index.ts` (throttle) und ggf. `panel.ts`.

- [ ] **Step 1: Throttled requestRender**

In `index.ts` das `engine.subscribe(() => panelHandle?.requestRender())` durch einen einfachen Drossel-Wrapper ersetzen (max. ~10/s):

```ts
	let renderQueued = false;
	const requestPanelRender = () => {
		if (renderQueued || !panelHandle) return;
		renderQueued = true;
		setTimeout(() => { renderQueued = false; panelHandle?.requestRender(); }, 100);
	};
	engine.subscribe(() => requestPanelRender());
```

Zusätzlich: damit auch das Streaming des *gewählten* Actors live nachzieht, abonniert `SwarmPanel.rebindView()` die View-Events und ruft einen injizierten `onActivity` (= `requestPanelRender`). `onActivity` in `SwarmPanelDeps` ergänzen und in `rebindView`/`subscribe`-Callback aufrufen.

- [ ] **Step 2: `node --check` + pure suite green.**

- [ ] **Step 3: Commit**

```bash
git add .../actor-swarm/index.ts .../actor-swarm/panel.ts
git commit -m "feat(actor-swarm): throttled live panel updates incl. selected-actor streaming"
```

---

## Task 7: Nix-Build + manuelle End-to-End-Verifikation

- [ ] **Step 1: Build (keine Aktivierung)**

```bash
cd ~/projects/dotfiles
nixos-rebuild build --flake .#gurke 2>&1 | tail -5
```
Erwartung: Build OK. (Die neuen Dateien liegen im selben `actor-swarm/`-Subdir → automatisch mitverlinkt.)

- [ ] **Step 2: Manuelle Verifikation (Nutzer: `nrs` + `/reload`)**

1. Oben erscheint dauerhaft das kompakte Panel mit der `user`-Zeile (`Name · Kontext · idle/active`).
2. `spawn_agent` einen `echo`-Actor → er taucht in der Liste auf, mit Kontext-Spalte.
3. `Ctrl+Q` → Panel expandiert; `↑/↓` wählt `echo`; das Transcript erscheint; Tippen landet in der Chatbox; `Enter` schickt an `echo`; dessen Antwort streamt live im Transcript.
4. `↑` auf `user` → Transcript zeigt „= Haupt-Chat unten".
5. `PgUp/PgDn` scrollt ein langes Transcript; `Esc`/`Ctrl+Q` gibt den Fokus zurück, Panel kollabiert.
6. Kontext-/aktiv-Status aktualisiert sich live, während ein Actor arbeitet.

- [ ] **Step 3: Spec-Abgleich**

Falls beim Bauen `ToolExecutionComponent`-Verzicht/Message-Mapping vom Spec abweicht, Spec-Abschnitt „Wiederverwendung" entsprechend nachziehen und committen.

---

## Notes / Known Phase-2 limitations (intentional)

- `ToolExecutionComponent` wird nicht wiederverwendet (zu stark gekoppelt); Tool-Calls erscheinen als Einzeiler.
- `user`-Transcript wird nicht ins Panel gespiegelt (es ist der Haupt-Chat).
- Kein Unread-/Attention-Marker, kein Kill-from-panel, kein Picker/Cycle, keine Maus, keine Suche (alles YAGNI; additiv).
- Scroll-Viewport ist eine feste Zeilenhöhe (z.B. 12); dynamische Höhe nach Terminalgröße ist eine spätere Politur.
```
