# Actor-Swarm pi-Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine pi-Extension, in der benannte Agent-Sessions („Actors") sich gegenseitig fire-and-forget Nachrichten per Tool-Call schicken, neue Actors zur Laufzeit erzeugen, und der Mensch (Vordergrund-TUI) als Actor `user` teilnimmt — alles in einem Prozess.

**Architecture:** Eine reine, SDK-freie `Engine` (Registry + Caps + Routing + Turn-Budget + Halt-State + Event-Log) wird über `globalThis` als Singleton gehalten. Die Vordergrund-Extension registriert Tools/Commands für `user` und erzeugt Hintergrund-Actors via SDK `createAgentSession` (isoliert über leeres `agentDir`, mit namensgebundenen `customTools`). Zustellung über `AgentSession.sendUserMessage(text, { deliverAs: "followUp" })`. Beobachtbarkeit read-only über Status-Footer und `/actors` / `/feed`.

**Tech Stack:** TypeScript (von pi via jiti geladen), `@earendil-works/pi-coding-agent` SDK, `typebox` für Tool-Parameter, `node:test` + `node:assert` für Unit-Tests (Node v24 native `.ts`-Ausführung), Nix/home-manager fürs Deployment.

**Spec:** `docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md`

---

## File Structure

```
modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/
  engine.ts        # SDK-frei: Typen, Engine-Klasse (Registry, Caps, Routing, Budget, Halt, Event-Log)
  engine.test.ts   # node:test Unit-Tests für engine.ts
  feed.ts          # SDK-frei: reine Formatierung (Status-Zeile, /actors-Snapshot, /feed-Zeilen)
  feed.test.ts     # node:test Unit-Tests für feed.ts
  index.ts         # pi-Entry: globalThis-Engine, spawnActor (SDK), Tools, Commands, Status, Subscriptions
modules/home-manager/profiles/ai-agents/pi-extensions.nix   # erweitern: Subdirs mit index.ts verlinken
```

Verantwortlichkeiten:
- `engine.ts` kennt **kein** pi-SDK. Es definiert eine schmale `ActorHandle`-Schnittstelle (`deliver`/`abort`/`isStreaming`) und arbeitet nur damit. Dadurch voll unit-testbar ohne LLM.
- `feed.ts` kennt nur Typen aus `engine.ts` und macht reine String-Formatierung.
- `index.ts` ist die einzige Datei mit SDK-/TUI-Abhängigkeiten und Seiteneffekten.

**Wichtig zur Discovery (verifiziert in pi 0.79.1 `core/extensions/loader.js`):** Ein Unterverzeichnis wird über genau `index.ts` als *eine* Extension geladen; `engine.ts`, `feed.ts`, `*.test.ts` werden **nicht** separat geladen. Test-Dateien im Subdir sind für pi inert.

---

## Task 1: Engine — Registry, Caps, Event-Log

**Files:**
- Create: `modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.ts`
- Test: `modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.test.ts`

- [ ] **Step 1: Write the failing test**

Create `engine.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { Engine, type ActorHandle } from "./engine.ts";

const fakeHandle = (): ActorHandle => ({
	deliver: async () => {},
	abort: async () => {},
	isStreaming: () => false,
});

const caps = { maxActors: 2, maxSpawnDepth: 2, turnBudget: 5 };

function userRecord() {
	return {
		name: "user",
		model: "anthropic/x",
		handle: fakeHandle(),
		spawnedBy: "user",
		depth: 0,
		createdAt: 0,
		turns: 0,
		lastActivity: 0,
		streaming: false,
	};
}

test("addActor registers and has/get work, emits spawn event", () => {
	const e = new Engine(caps);
	e.addActor(userRecord());
	assert.equal(e.has("user"), true);
	assert.equal(e.get("user")?.depth, 0);
	assert.equal(e.list().length, 1);
	assert.equal(e.events.at(-1)?.type, "spawn");
});

test("canSpawn rejects duplicate name", () => {
	const e = new Engine(caps);
	e.addActor(userRecord());
	const r = e.canSpawn("user", 0);
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /already exists/);
});

test("canSpawn rejects reserved name and invalid name", () => {
	const e = new Engine(caps);
	assert.equal(e.canSpawn("user", 0).ok, false); // reserved
	assert.equal(e.canSpawn("has space", 0).ok, false);
	assert.equal(e.canSpawn("", 0).ok, false);
});

test("canSpawn enforces maxActors (excluding user)", () => {
	const e = new Engine(caps); // maxActors = 2
	e.addActor(userRecord());
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.addActor({ ...userRecord(), name: "b", depth: 1 });
	const r = e.canSpawn("c", 0);
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /max actors/i);
});

test("canSpawn enforces maxSpawnDepth", () => {
	const e = new Engine(caps); // maxSpawnDepth = 2
	const r = e.canSpawn("deep", 2); // spawnerDepth 2 -> child depth 3 > 2
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /depth/i);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm && node --test engine.test.ts`
Expected: FAIL — `Cannot find module './engine.ts'` / `Engine is not defined`.

- [ ] **Step 3: Write minimal implementation**

Create `engine.ts`:

```ts
/**
 * Actor-Swarm Engine — reine Policy + Registry, ohne pi-SDK-Abhängigkeit.
 * Design: docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md
 */

export interface ActorHandle {
	/** Stellt eine bereits formatierte Nachricht zu (Mailbox-Semantik im Adapter). */
	deliver(text: string): Promise<void>;
	/** Bricht den laufenden Turn dieses Actors ab. */
	abort(): Promise<void>;
	/** Ob der Actor gerade streamt (nur für Statusanzeige). */
	isStreaming(): boolean;
}

export interface ActorRecord {
	name: string;
	model: string; // "provider/id" nur zur Anzeige
	handle: ActorHandle;
	spawnedBy: string;
	depth: number; // user = 0
	createdAt: number;
	turns: number;
	lastActivity: number;
	streaming: boolean;
}

export interface Caps {
	maxActors: number; // ohne 'user'
	maxSpawnDepth: number;
	turnBudget: number; // global über alle Hintergrund-Actors
}

export type SwarmEvent =
	| { type: "spawn"; name: string; by: string; ts: number }
	| { type: "route"; from: string; to: string; preview: string; ts: number }
	| { type: "turn"; name: string; ts: number }
	| { type: "halt"; ts: number }
	| { type: "resume"; ts: number }
	| { type: "blocked"; reason: string; ts: number };

export type CheckResult = { ok: true } | { ok: false; reason: string };

const RESERVED = new Set(["user"]);
const NAME_RE = /^[a-zA-Z0-9_-]+$/;

export class Engine {
	readonly events: SwarmEvent[] = [];
	private readonly actors = new Map<string, ActorRecord>();
	private readonly listeners = new Set<(e: SwarmEvent) => void>();
	private frozen = false;
	private turnsUsed = 0;

	constructor(private readonly caps: Caps) {}

	private emit(e: SwarmEvent): void {
		this.events.push(e);
		for (const l of this.listeners) l(e);
	}

	subscribe(l: (e: SwarmEvent) => void): () => void {
		this.listeners.add(l);
		return () => this.listeners.delete(l);
	}

	has(name: string): boolean {
		return this.actors.has(name);
	}

	get(name: string): ActorRecord | undefined {
		return this.actors.get(name);
	}

	list(): ActorRecord[] {
		return [...this.actors.values()];
	}

	get budget(): { used: number; total: number } {
		return { used: this.turnsUsed, total: this.caps.turnBudget };
	}

	canSpawn(name: string, spawnerDepth: number): CheckResult {
		if (RESERVED.has(name)) return { ok: false, reason: `name '${name}' is reserved` };
		if (!NAME_RE.test(name)) return { ok: false, reason: `invalid name '${name}' (use [a-zA-Z0-9_-])` };
		if (this.actors.has(name)) return { ok: false, reason: `actor '${name}' already exists` };
		const backgroundCount = [...this.actors.values()].filter((a) => a.name !== "user").length;
		if (backgroundCount >= this.caps.maxActors) {
			return { ok: false, reason: `max actors reached (${this.caps.maxActors})` };
		}
		if (spawnerDepth + 1 > this.caps.maxSpawnDepth) {
			return { ok: false, reason: `max spawn depth reached (${this.caps.maxSpawnDepth})` };
		}
		return { ok: true };
	}

	addActor(rec: ActorRecord): void {
		this.actors.set(rec.name, rec);
		this.emit({ type: "spawn", name: rec.name, by: rec.spawnedBy, ts: Date.now() });
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm && node --test engine.test.ts`
Expected: PASS — 5 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.ts modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.test.ts
git commit -m "feat(actor-swarm): engine registry + spawn caps"
```

---

## Task 2: Engine — Routing (fire-and-forget Zustellung)

**Files:**
- Modify: `actor-swarm/engine.ts` (add `route` method)
- Test: `actor-swarm/engine.test.ts` (append tests)

- [ ] **Step 1: Write the failing test**

Append to `engine.test.ts`:

```ts
test("route delivers prefixed message to existing actor when idle", async () => {
	const e = new Engine(caps);
	let delivered = "";
	const handle: ActorHandle = {
		deliver: async (t) => {
			delivered = t;
		},
		abort: async () => {},
		isStreaming: () => false,
	};
	e.addActor({ ...userRecord(), name: "coder", handle, depth: 1 });
	const r = await e.route("user", "coder", "fix the bug");
	assert.equal(r.ok, true);
	assert.equal(delivered, "[message from user]: fix the bug");
	assert.match((r as { status: string }).status, /woken|delivered/i);
	assert.equal(e.events.at(-1)?.type, "route");
});

test("route reports busy status when target is streaming", async () => {
	const e = new Engine(caps);
	const handle: ActorHandle = {
		deliver: async () => {},
		abort: async () => {},
		isStreaming: () => true,
	};
	e.addActor({ ...userRecord(), name: "busy", handle, depth: 1 });
	const r = await e.route("user", "busy", "hi");
	assert.equal(r.ok, true);
	assert.match((r as { status: string }).status, /queued|busy/i);
});

test("route fails for unknown actor", async () => {
	const e = new Engine(caps);
	const r = await e.route("user", "ghost", "hi");
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /unknown actor/i);
});

test("route is blocked while frozen", async () => {
	const e = new Engine(caps);
	e.addActor({ ...userRecord(), name: "coder", depth: 1 });
	e.halt();
	const r = await e.route("user", "coder", "hi");
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /halt/i);
	assert.equal(e.events.at(-1)?.type, "blocked");
});
```

(Note: `e.halt()` is added in Task 3 but referenced here; if running Task 2 in isolation, the "frozen" test will fail to compile. Implement `halt`/`isFrozen` minimal stub in this task too — see Step 3.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd actor-swarm && node --test engine.test.ts`
Expected: FAIL — `route is not a function` (and `halt`).

- [ ] **Step 3: Write minimal implementation**

In `engine.ts`, add inside the `Engine` class (after `addActor`):

```ts
	isFrozen(): boolean {
		return this.frozen;
	}

	halt(): void {
		this.frozen = true;
		this.emit({ type: "halt", ts: Date.now() });
	}

	async route(from: string, to: string, content: string): Promise<{ ok: true; status: string } | { ok: false; reason: string }> {
		if (this.frozen) {
			const reason = "swarm halted (use /resume)";
			this.emit({ type: "blocked", reason, ts: Date.now() });
			return { ok: false, reason };
		}
		const target = this.actors.get(to);
		if (!target) return { ok: false, reason: `unknown actor '${to}'` };
		const text = `[message from ${from}]: ${content}`;
		const wasStreaming = target.handle.isStreaming();
		await target.handle.deliver(text);
		target.lastActivity = Date.now();
		const preview = content.length > 60 ? `${content.slice(0, 60)}...` : content;
		this.emit({ type: "route", from, to, preview, ts: Date.now() });
		return { ok: true, status: wasStreaming ? "queued (busy)" : "delivered (woken)" };
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd actor-swarm && node --test engine.test.ts`
Expected: PASS — all tests (9 total).

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.ts modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.test.ts
git commit -m "feat(actor-swarm): message routing with prefix + busy/halt handling"
```

---

## Task 3: Engine — Halt/Resume + Turn-Budget + Streaming-State

**Files:**
- Modify: `actor-swarm/engine.ts` (add `resume`, `recordTurnStart`, `setStreaming`)
- Test: `actor-swarm/engine.test.ts` (append tests)

- [ ] **Step 1: Write the failing test**

Append to `engine.test.ts`:

```ts
test("recordTurnStart counts turns and aborts when budget exhausted", () => {
	const e = new Engine({ maxActors: 5, maxSpawnDepth: 5, turnBudget: 2 });
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	assert.equal(e.recordTurnStart("a").abort, false);
	assert.equal(e.recordTurnStart("a").abort, false);
	const third = e.recordTurnStart("a");
	assert.equal(third.abort, true);
	assert.match(third.reason ?? "", /budget/i);
	assert.equal(e.get("a")?.turns, 2);
	assert.equal(e.budget.used, 2);
});

test("recordTurnStart aborts while frozen", () => {
	const e = new Engine(caps);
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.halt();
	const r = e.recordTurnStart("a");
	assert.equal(r.abort, true);
	assert.match(r.reason ?? "", /halt/i);
});

test("resume clears frozen and resets budget", () => {
	const e = new Engine({ maxActors: 5, maxSpawnDepth: 5, turnBudget: 1 });
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.recordTurnStart("a"); // uses budget
	e.halt();
	e.resume();
	assert.equal(e.isFrozen(), false);
	assert.equal(e.budget.used, 0);
	assert.equal(e.events.at(-1)?.type, "resume");
	assert.equal(e.recordTurnStart("a").abort, false);
});

test("setStreaming updates record flag", () => {
	const e = new Engine(caps);
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.setStreaming("a", true);
	assert.equal(e.get("a")?.streaming, true);
	e.setStreaming("a", false);
	assert.equal(e.get("a")?.streaming, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd actor-swarm && node --test engine.test.ts`
Expected: FAIL — `resume`/`recordTurnStart`/`setStreaming` not functions.

- [ ] **Step 3: Write minimal implementation**

In `engine.ts`, add inside the `Engine` class (after `halt`):

```ts
	resume(): void {
		this.frozen = false;
		this.turnsUsed = 0;
		this.emit({ type: "resume", ts: Date.now() });
	}

	/** Vor jedem Hintergrund-Turn aufrufen. abort=true => Caller muss session.abort() aufrufen. */
	recordTurnStart(name: string): { abort: boolean; reason?: string } {
		if (this.frozen) return { abort: true, reason: "swarm halted" };
		if (this.turnsUsed >= this.caps.turnBudget) {
			return { abort: true, reason: `turn budget exhausted (${this.caps.turnBudget})` };
		}
		this.turnsUsed++;
		const rec = this.actors.get(name);
		if (rec) {
			rec.turns++;
			rec.lastActivity = Date.now();
		}
		this.emit({ type: "turn", name, ts: Date.now() });
		return { abort: false };
	}

	setStreaming(name: string, streaming: boolean): void {
		const rec = this.actors.get(name);
		if (rec) rec.streaming = streaming;
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd actor-swarm && node --test engine.test.ts`
Expected: PASS — all tests (13 total).

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.ts modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/engine.test.ts
git commit -m "feat(actor-swarm): halt/resume, turn budget, streaming state"
```

---

## Task 4: Feed — reine Formatierung (Status, /actors, /feed)

**Files:**
- Create: `actor-swarm/feed.ts`
- Test: `actor-swarm/feed.test.ts`

- [ ] **Step 1: Write the failing test**

Create `feed.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { formatStatus, formatSnapshot, formatFeedLines } from "./feed.ts";
import type { ActorRecord, SwarmEvent } from "./engine.ts";

const rec = (over: Partial<ActorRecord>): ActorRecord => ({
	name: "a",
	model: "anthropic/x",
	handle: { deliver: async () => {}, abort: async () => {}, isStreaming: () => false },
	spawnedBy: "user",
	depth: 1,
	createdAt: 0,
	turns: 0,
	lastActivity: 0,
	streaming: false,
	...over,
});

test("formatStatus summarises counts and budget", () => {
	const s = formatStatus(3, 1, 7, 100);
	assert.match(s, /3 actors/);
	assert.match(s, /1 running/);
	assert.match(s, /7\/100/);
});

test("formatSnapshot lists each actor with status and turns", () => {
	const actors = [
		rec({ name: "user", depth: 0, model: "anthropic/opus" }),
		rec({ name: "coder", streaming: true, turns: 4 }),
	];
	const out = formatSnapshot(actors, 4, 100);
	assert.match(out, /user/);
	assert.match(out, /coder/);
	assert.match(out, /running/);
	assert.match(out, /idle/);
	assert.match(out, /4/);
});

test("formatFeedLines renders one line per event newest-aware", () => {
	const events: SwarmEvent[] = [
		{ type: "spawn", name: "coder", by: "user", ts: 0 },
		{ type: "route", from: "user", to: "coder", preview: "do x", ts: 0 },
		{ type: "halt", ts: 0 },
	];
	const lines = formatFeedLines(events);
	assert.equal(lines.length, 3);
	assert.match(lines[0], /spawn.*coder/);
	assert.match(lines[1], /user.*->.*coder/);
	assert.match(lines[2], /halt/i);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd actor-swarm && node --test feed.test.ts`
Expected: FAIL — `Cannot find module './feed.ts'`.

- [ ] **Step 3: Write minimal implementation**

Create `feed.ts`:

```ts
/**
 * Reine Formatierung für die read-only Beobachtbarkeit des Swarms.
 * Keine pi-/TUI-Abhängigkeit; die Strings werden in index.ts in UI gerendert.
 */
import type { ActorRecord, SwarmEvent } from "./engine.ts";

export function formatStatus(actorCount: number, runningCount: number, turnsUsed: number, turnBudget: number): string {
	return `swarm: ${actorCount} actors · ${runningCount} running · budget ${turnsUsed}/${turnBudget}`;
}

export function formatSnapshot(actors: ActorRecord[], turnsUsed: number, turnBudget: number): string {
	if (actors.length === 0) return "no actors";
	const rows = actors.map((a) => {
		const status = a.streaming ? "running" : "idle";
		return `  ${a.name.padEnd(14)} ${status.padEnd(8)} turns:${a.turns}  ${a.model}  (by ${a.spawnedBy}, depth ${a.depth})`;
	});
	return [`actors (budget ${turnsUsed}/${turnBudget}):`, ...rows].join("\n");
}

export function formatFeedLines(events: SwarmEvent[]): string[] {
	return events.map((e) => {
		switch (e.type) {
			case "spawn":
				return `spawn   ${e.name} (by ${e.by})`;
			case "route":
				return `route   ${e.from} -> ${e.to}: ${e.preview}`;
			case "turn":
				return `turn    ${e.name}`;
			case "halt":
				return `HALT`;
			case "resume":
				return `RESUME`;
			case "blocked":
				return `blocked ${e.reason}`;
		}
	});
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd actor-swarm && node --test feed.test.ts`
Expected: PASS — 3 tests.

- [ ] **Step 5: Run the full suite**

Run: `cd actor-swarm && node --test`
Expected: PASS — 16 tests across both files.

- [ ] **Step 6: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/feed.ts modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/feed.test.ts
git commit -m "feat(actor-swarm): read-only feed/status/snapshot formatting"
```

---

## Task 5: index.ts — Engine-Singleton, Tools, Spawn (SDK)

**Files:**
- Create: `actor-swarm/index.ts`

Dies ist die SDK-/TUI-Schicht; sie wird nicht per `node:test` getestet (braucht echtes Modell), sondern in Task 7 manuell verifiziert. Logik steckt in der getesteten Engine.

- [ ] **Step 1: Write index.ts (full)**

Create `index.ts`:

```ts
/**
 * Actor-Swarm pi-Extension — Vordergrund-Entry.
 * Hält die Engine als globalThis-Singleton (überlebt /reload), registriert Tools
 * + Commands für den 'user'-Actor und erzeugt Hintergrund-Actors via SDK.
 * Design: docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md
 */
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
	AuthStorage,
	createAgentSession,
	DefaultResourceLoader,
	type ExtensionAPI,
	ModelRegistry,
	SessionManager,
	type ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { Engine, type ActorHandle } from "./engine.ts";
import { formatFeedLines, formatSnapshot, formatStatus } from "./feed.ts";

// Caps — Phase 1: Modul-Konstanten (Settings-Binding ist eine triviale spätere Ergänzung).
const CAPS = { maxActors: 8, maxSpawnDepth: 3, turnBudget: 100 };

const ENGINE_KEY = "__actorSwarmEngine_v1";

function getEngine(): Engine {
	const g = globalThis as Record<string, unknown>;
	if (!g[ENGINE_KEY]) g[ENGINE_KEY] = new Engine(CAPS);
	return g[ENGINE_KEY] as Engine;
}

function actorSystemPrompt(name: string, role: string): string {
	return [
		`You are actor "${name}" in a multi-agent swarm.`,
		"You can talk to other actors with these tools:",
		"- spawn_agent({name, role, model?, tools?}): create a new actor.",
		"- send_message({to, content}): fire-and-forget message to another actor (e.g. 'user').",
		"- list_agents(): see who exists.",
		"Messages you receive are prefixed with [message from <sender>].",
		"To reply, use send_message back to that sender.",
		"",
		"Your role:",
		role,
	].join("\n");
}

export default function actorSwarm(pi: ExtensionAPI) {
	const engine = getEngine();

	// Process-global, einmalig aufgebaute Dienste (gleiche creds wie Vordergrund).
	const authStorage = AuthStorage.create();
	const modelRegistry = ModelRegistry.create(authStorage);

	// Leeres agentDir, damit Hintergrund-Sessions NICHT erneut Extensions/Skills laden.
	const blankAgentDir = fs.mkdtempSync(path.join(os.tmpdir(), "actor-swarm-"));

	// UI ist nur über ctx.ui (ExtensionUIContext) verfügbar, nicht auf `pi`.
	// Wir cachen die Referenz aus session_start, um den Footer auch aus
	// Engine-Events (außerhalb eines Handler-ctx) aktualisieren zu können.
	type UI = { setStatus(key: string, text: string | undefined): void };
	let ui: UI | undefined;
	let cwd = process.cwd();
	let lastForegroundModel: { provider: string; id: string } | undefined;
	let foregroundStreaming = false;

	const updateStatus = () => {
		const actors = engine.list();
		const running = actors.filter((a) => a.streaming).length;
		const { used, total } = engine.budget;
		ui?.setStatus("swarm", formatStatus(actors.length, running, used, total));
	};

	// Status bei jedem Engine-Event aktualisieren.
	engine.subscribe(() => updateStatus());

	const resolveModel = (ref: string | undefined) => {
		const r = ref ?? (lastForegroundModel ? `${lastForegroundModel.provider}/${lastForegroundModel.id}` : undefined);
		if (!r) return undefined;
		const slash = r.indexOf("/");
		if (slash < 0) return undefined;
		return modelRegistry.find(r.slice(0, slash), r.slice(slash + 1));
	};

	// Tools für einen bestimmten Actor (Name fest gebunden) — für Vordergrund 'user'
	// via pi.registerTool und für Hintergrund-Actors via customTools verwendet.
	const makeActorTools = (selfName: string): ToolDefinition[] => [
		{
			name: "spawn_agent",
			label: "Spawn Agent",
			description: "Create a new actor with a role/system prompt. It can then be messaged by name.",
			parameters: Type.Object({
				name: Type.String({ description: "Unique actor name ([a-zA-Z0-9_-])" }),
				role: Type.String({ description: "System prompt describing the actor's role" }),
				model: Type.Optional(Type.String({ description: "provider/id; default: inherited" })),
				tools: Type.Optional(Type.Array(Type.String(), { description: "Built-in tool allowlist" })),
			}),
			execute: async (_id, args) => {
				const res = await spawnActor(args, selfName);
				return { content: [{ type: "text", text: res.msg }], details: {} };
			},
		},
		{
			name: "send_message",
			label: "Send Message",
			description: "Fire-and-forget message to another actor (e.g. 'user'). Returns immediately.",
			parameters: Type.Object({
				to: Type.String({ description: "Target actor name" }),
				content: Type.String({ description: "Message content" }),
			}),
			execute: async (_id, args) => {
				const r = await engine.route(selfName, args.to, args.content);
				const text = r.ok ? `queued to '${args.to}' (${r.status})` : `error: ${r.reason}`;
				return { content: [{ type: "text", text }], details: {} };
			},
		},
		{
			name: "list_agents",
			label: "List Agents",
			description: "List all actors and their status.",
			parameters: Type.Object({}),
			execute: async () => {
				const { used, total } = engine.budget;
				return { content: [{ type: "text", text: formatSnapshot(engine.list(), used, total) }], details: {} };
			},
		},
	];

	const subscribeBackground = (name: string, session: { isStreaming: boolean; abort(): Promise<void>; subscribe(l: (e: { type: string }) => void): () => void }) => {
		session.subscribe((ev) => {
			if (ev.type === "turn_start") {
				const r = engine.recordTurnStart(name);
				if (r.abort) void session.abort();
			}
			if (ev.type === "agent_start" || ev.type === "message_start") engine.setStreaming(name, true);
			if (ev.type === "agent_end") engine.setStreaming(name, false);
			updateStatus();
		});
	};

	async function spawnActor(
		spec: { name: string; role: string; model?: string; tools?: string[] },
		spawnerName: string,
	): Promise<{ ok: boolean; msg: string }> {
		const spawner = engine.get(spawnerName);
		const depth = spawner ? spawner.depth : 0;
		const check = engine.canSpawn(spec.name, depth);
		if (!check.ok) return { ok: false, msg: `error: ${check.reason}` };

		const inheritRef = spec.model ?? spawner?.model;
		const model = resolveModel(inheritRef);
		if (!model) return { ok: false, msg: `error: unknown model '${inheritRef ?? "(none)"}'` };

		const loader = new DefaultResourceLoader({
			cwd,
			agentDir: blankAgentDir,
			systemPromptOverride: () => actorSystemPrompt(spec.name, spec.role),
		});
		await loader.reload();

		const toolAllowlist = spec.tools ? [...spec.tools, "spawn_agent", "send_message", "list_agents"] : undefined;

		const { session } = await createAgentSession({
			cwd,
			model,
			authStorage,
			modelRegistry,
			customTools: makeActorTools(spec.name),
			...(toolAllowlist ? { tools: toolAllowlist } : {}),
			resourceLoader: loader,
			sessionManager: SessionManager.inMemory(cwd),
		});

		const handle: ActorHandle = {
			deliver: async (text) => {
				await session.sendUserMessage(text, { deliverAs: "followUp" });
			},
			abort: async () => {
				await session.abort();
			},
			isStreaming: () => session.isStreaming,
		};

		engine.addActor({
			name: spec.name,
			model: `${model.provider}/${model.id}`,
			handle,
			spawnedBy: spawnerName,
			depth: depth + 1,
			createdAt: Date.now(),
			turns: 0,
			lastActivity: Date.now(),
			streaming: false,
		});
		subscribeBackground(spec.name, session);
		return { ok: true, msg: `spawned '${spec.name}' (model ${model.provider}/${model.id})` };
	}

	// Foreground-Modell erfassen (für Vererbung an gespawnte Actors).
	pi.on("model_select", (event) => {
		lastForegroundModel = { provider: event.model.provider, id: event.model.id };
		const u = engine.get("user");
		if (u) u.model = `${event.model.provider}/${event.model.id}`;
	});

	// Foreground-Streaming-Flag für Statusanzeige.
	pi.on("agent_start", () => {
		foregroundStreaming = true;
		engine.setStreaming("user", true);
		updateStatus();
	});
	pi.on("agent_end", () => {
		foregroundStreaming = false;
		engine.setStreaming("user", false);
		updateStatus();
	});

	// 'user'-Actor registrieren (Vordergrund). Zustellung an user via pi.sendUserMessage.
	pi.on("session_start", (_event, ctx) => {
		cwd = ctx.cwd;
		ui = ctx.ui;
		if (!engine.has("user")) {
			const userHandle: ActorHandle = {
				deliver: async (text) => {
					pi.sendUserMessage(text, { deliverAs: "followUp" });
				},
				abort: async () => {}, // den Menschen-Turn nicht abbrechen
				isStreaming: () => foregroundStreaming,
			};
			engine.addActor({
				name: "user",
				model: lastForegroundModel ? `${lastForegroundModel.provider}/${lastForegroundModel.id}` : "(foreground)",
				handle: userHandle,
				spawnedBy: "user",
				depth: 0,
				createdAt: Date.now(),
				turns: 0,
				lastActivity: Date.now(),
				streaming: false,
			});
		}
		updateStatus();
	});

	// Vordergrund-Tools für 'user' registrieren.
	for (const tool of makeActorTools("user")) {
		pi.registerTool(tool);
	}
}
```

- [ ] **Step 2: Verify it parses (type-strip syntax check)**

Run: `cd modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm && node --experimental-strip-types --check index.ts`
Expected: no output, exit 0 (syntax OK). Imports are not resolved by `--check`; full runtime verification is in Task 7.

If `--check` rejects `.ts`, fall back to: `node --experimental-strip-types -e "import('./index.ts').catch(()=>{})"` is NOT reliable (resolves bundled imports). In that case skip to Task 7 for runtime verification and rely on the engine/feed tests here.

- [ ] **Step 3: Run the engine/feed suite to confirm no regressions**

Run: `cd actor-swarm && node --test`
Expected: PASS — 16 tests.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/index.ts
git commit -m "feat(actor-swarm): foreground entry, tools, SDK spawn of actors"
```

---

## Task 6: index.ts — Commands (/halt, /resume, /actors, /feed)

**Files:**
- Modify: `actor-swarm/index.ts` (add command registrations before the closing `}` of the default export)

- [ ] **Step 1: Add command registrations**

In `index.ts`, add immediately after the `for (const tool of makeActorTools("user")) { pi.registerTool(tool); }` loop:

```ts
	pi.registerCommand("halt", {
		description: "Freeze the whole actor swarm (stop new turns, abort running background actors).",
		handler: async (_args, ctx) => {
			engine.halt();
			for (const a of engine.list()) {
				if (a.name !== "user") void a.handle.abort();
			}
			ctx.ui.notify("Swarm halted. Use /resume to continue.", "warning");
			updateStatus();
		},
	});

	pi.registerCommand("resume", {
		description: "Resume a halted swarm and reset the turn budget.",
		handler: async (_args, ctx) => {
			engine.resume();
			ctx.ui.notify("Swarm resumed; turn budget reset.", "info");
			updateStatus();
		},
	});

	pi.registerCommand("actors", {
		description: "Show the actor roster and status.",
		handler: async (_args, ctx) => {
			const { used, total } = engine.budget;
			ctx.ui.notify(formatSnapshot(engine.list(), used, total), "info");
		},
	});

	pi.registerCommand("feed", {
		description: "Show the swarm activity log (last 40 events).",
		handler: async (_args, ctx) => {
			const lines = formatFeedLines(engine.events).slice(-40);
			ctx.ui.notify(lines.length ? lines.join("\n") : "(no activity yet)", "info");
		},
	});
```

> Note: Phase 1 renders `/actors` and `/feed` via `ctx.ui.notify` (simple, reliable). The scrollable `ctx.ui.custom` overlay is a Phase 2 nicety and intentionally omitted (YAGNI).

- [ ] **Step 2: Verify it parses**

Run: `cd actor-swarm && node --experimental-strip-types --check index.ts`
Expected: exit 0 (or skip per Task 5 Step 2 fallback note).

- [ ] **Step 3: Confirm engine/feed suite still green**

Run: `cd actor-swarm && node --test`
Expected: PASS — 16 tests.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/index.ts
git commit -m "feat(actor-swarm): /halt, /resume, /actors, /feed commands"
```

---

## Task 7: Nix deployment + integration verification

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions.nix`

- [ ] **Step 1: Extend pi-extensions.nix to link subdirectories with index.ts**

Replace the body of `pi-extensions.nix` with:

```nix
# pi-spezifische Extensions in den Auto-Discovery-Pfad ~/.pi/agent/extensions/
# verlinken (siehe pi-Doku: extensions.md → "Extension Locations"). Top-Level-*.ts
# werden als einzelne Extensions verlinkt; Unterverzeichnisse mit index.ts als
# mehrdateiige Extensions (pi lädt nur deren index.ts; engine.ts/feed.ts/*.test.ts
# bleiben inert). Bearbeitung im Repo + Home-Manager-Switch; danach `/reload` in pi.
{lib, ...}: let
  dir = ./pi-extensions;
  entries = builtins.readDir dir;

  # Top-Level *.ts -> ~/.pi/agent/extensions/<name>
  files =
    lib.mapAttrs' (name: _: {
      name = ".pi/agent/extensions/${name}";
      value.source = dir + "/${name}";
    })
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".ts" name) entries);

  # Unterverzeichnisse mit index.ts -> ~/.pi/agent/extensions/<dir>
  subdirs =
    lib.mapAttrs' (name: _: {
      name = ".pi/agent/extensions/${name}";
      value.source = dir + "/${name}";
    })
    (lib.filterAttrs
      (name: type: type == "directory" && builtins.pathExists (dir + "/${name}/index.ts"))
      entries);
in {
  home.file = files // subdirs;
}
```

- [ ] **Step 2: Build the home-manager configuration (no activation)**

Run (stay on the current specialisation; build only — never switch):
```bash
cd ~/projects/dotfiles
nixos-rebuild build --flake .#$(hostname) 2>&1 | tail -20
```
Expected: builds without evaluation errors. (If your repo uses a different build entrypoint, use the same one `nrs` uses, build-only.)

- [ ] **Step 3: Verify the symlink target contents are present in the build**

Run:
```bash
ls result/ 2>/dev/null; echo "---"; cat result/home-path/.. 2>/dev/null || true
# Sanity: the extension dir exists in the repo with all files
ls modules/home-manager/profiles/ai-agents/pi-extensions/actor-swarm/
```
Expected: `engine.ts engine.test.ts feed.ts feed.test.ts index.ts` listed.

- [ ] **Step 4: Commit the nix change**

```bash
cd ~/projects/dotfiles
git add modules/home-manager/profiles/ai-agents/pi-extensions.nix
git commit -m "feat(actor-swarm): link multi-file pi extensions (subdir with index.ts)"
```

- [ ] **Step 5: Manual smoke test (user runs the system switch + pi)**

After the user activates the new home-manager generation (their `nrs`), the user verifies in an interactive `pi` session:

1. `/actors` → shows `user` actor, status idle, budget 0/100. Footer shows `swarm: 1 actors · …`.
2. Prompt: `Use spawn_agent to create an actor named "echo" with role "Reply to every message by sending it back to the sender via send_message.", then send_message to echo with content "ping".`
   - Expected: `spawned 'echo' …`, then `queued to 'echo' (delivered (woken))`.
   - Expected: a new user message `[message from echo]: …` appears in the chat and the foreground LLM reacts to it (per design decision #3).
3. `/actors` → shows `echo` with turns ≥ 1. `/feed` → shows `spawn echo`, `route user -> echo`, `turn echo` lines.
4. `/halt` → notify "Swarm halted"; further `send_message` returns `error: swarm halted`. `/resume` → works again.

- [ ] **Step 6: Update spec note on caps location (consistency)**

Since caps are module constants (not settings) in Phase 1, adjust the spec line to match reality:

In `docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md`, change
`Konfigurierbar über Extension-Settings, mit Defaults:` to
`Phase 1: Modul-Konstanten in index.ts (Settings-Binding ist additive Phase-2-Ergänzung), Defaults:`

Then:
```bash
cd ~/projects/dotfiles
git add docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md
git commit -m "docs(actor-swarm): caps are module constants in phase 1"
```

---

## Notes / Known Phase-1 limitations (documented, intentional)

- Background actors are in-memory; they do not persist across process exit.
- A foreground session switch (`/new`, `/resume`, `/fork`) keeps the globalThis engine and its running actors (they reconnect on reload). Actors are not auto-disposed on switch; rely on `/halt` to stop them.
- `escape` aborts only the foreground (`user`) turn, never the swarm (verified: extensions cannot rebind global keys; `/halt` is the swarm kill switch).
- `/actors` and `/feed` use `ctx.ui.notify`; a scrollable overlay is Phase 2.
- Background actors that ran bash tools may leave child processes if not `/halt`ed before exit (Phase-1 acceptable).
```
