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

/** Live-Sicht auf einen Actor für das Panel (Phase 2). Optional, rein additiv. */
export interface ActorView {
	getMessages(): unknown[];
	/** Der System-Prompt, mit dem der Actor läuft (oben im Transcript angezeigt). */
	getSystemPrompt?(): string;
	getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined;
	subscribe(listener: (e: { type: string }) => void): () => void;
}

export interface ActorRecord {
	name: string;
	model: string; // "provider/id" nur zur Anzeige
	handle: ActorHandle;
	/** Optional: Live-Sicht auf Transcript/Kontext/Events (für das Panel). */
	view?: ActorView;
	spawnedBy: string;
	depth: number; // user = 0
	createdAt: number;
	turns: number;
	lastActivity: number;
	streaming: boolean;
	/** Reservierungs-Zwischenzustand: Name belegt, Session wird noch erstellt. */
	pending?: boolean;
	/** Während pending gepufferte Nachrichten (bei attach an die Session geflusht). */
	buffer?: string[];
	/** Aufräumfunktion (z.B. Event-Subscription lösen) — beim Kill aufgerufen. */
	dispose?: () => void;
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
	| { type: "kill"; name: string; ts: number }
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
	private readonly caps: Caps;

	// Hinweis: keine TS-Parameter-Properties verwenden — Node's strip-only-Modus
	// (node --test auf .ts) unterstützt sie nicht.
	constructor(caps: Caps) {
		this.caps = caps;
	}

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

	// --- Atomare Reservierung (verhindert Spawn/Send-, Duplikat- und Cap-Races) ---
	// canSpawn (sync) ist von der langsamen Session-Erstellung durch ein await getrennt;
	// reserve schließt den Namen synchron ein, attach füllt die echte Session nach.

	/** Reserviert einen Actor-Namen synchron. Gepufferte Nachrichten bis attach. */
	reserve(name: string, spawnerName: string): CheckResult {
		const spawner = this.actors.get(spawnerName);
		const depth = spawner ? spawner.depth : 0;
		const check = this.canSpawn(name, depth);
		if (!check.ok) return check;
		const buffer: string[] = [];
		const record: ActorRecord = {
			name,
			model: "(spawning)",
			handle: {
				deliver: async (t) => {
					buffer.push(t);
				},
				abort: async () => {},
				isStreaming: () => false,
			},
			spawnedBy: spawnerName,
			depth: depth + 1,
			createdAt: Date.now(),
			turns: 0,
			lastActivity: Date.now(),
			streaming: false,
			pending: true,
			buffer,
		};
		this.actors.set(name, record);
		this.emit({ type: "spawn", name, by: spawnerName, ts: Date.now() });
		return { ok: true };
	}

	/** Schließt eine Reservierung ab: echte Session-Daten setzen + Puffer flushen. */
	attach(name: string, opts: { model: string; handle: ActorHandle; view?: ActorView; dispose?: () => void }): void {
		const rec = this.actors.get(name);
		if (!rec) return;
		rec.model = opts.model;
		rec.handle = opts.handle;
		rec.view = opts.view;
		rec.dispose = opts.dispose;
		rec.pending = false;
		const buffered = rec.buffer ?? [];
		rec.buffer = undefined;
		for (const t of buffered) void opts.handle.deliver(t);
	}

	/** Reservierung freigeben (Session-Erstellung fehlgeschlagen). */
	release(name: string): void {
		this.actors.delete(name);
	}

	/** Einen Actor terminieren (poison-pill): Turn abbrechen, aufräumen, entfernen. 'user' ist tabu. */
	kill(name: string): CheckResult {
		if (name === "user") return { ok: false, reason: "cannot kill 'user'" };
		const rec = this.actors.get(name);
		if (!rec) return { ok: false, reason: `unknown actor '${name}'` };
		void rec.handle.abort();
		rec.dispose?.();
		this.actors.delete(name);
		this.emit({ type: "kill", name, ts: Date.now() });
		return { ok: true };
	}

	/** Alle Actors außer 'user' killen. Gibt die Namen der gekillten zurück. */
	killAll(): string[] {
		const killed: string[] = [];
		for (const name of [...this.actors.keys()]) {
			if (name === "user") continue;
			if (this.kill(name).ok) killed.push(name);
		}
		return killed;
	}

	isFrozen(): boolean {
		return this.frozen;
	}

	halt(): void {
		this.frozen = true;
		this.emit({ type: "halt", ts: Date.now() });
	}

	resume(): void {
		this.frozen = false;
		this.turnsUsed = 0;
		this.emit({ type: "resume", ts: Date.now() });
	}

	async route(
		from: string,
		to: string,
		content: string,
	): Promise<{ ok: true; status: string } | { ok: false; reason: string }> {
		if (this.frozen) {
			const reason = "swarm halted (use /unhalt)";
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
}
