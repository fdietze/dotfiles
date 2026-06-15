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
