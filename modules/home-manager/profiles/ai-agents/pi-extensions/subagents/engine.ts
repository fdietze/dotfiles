/**
 * Subagents Engine — pure policy + registry, no pi-SDK dependency.
 * Design: docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md
 */

export interface AgentHandle {
	/** Delivers an already-formatted message (mailbox semantics live in the adapter). */
	deliver(text: string): Promise<void>;
	/** Aborts this agent's running turn. */
	abort(): Promise<void>;
	/** Whether the agent is currently streaming (status display only). */
	isStreaming(): boolean;
}

/** Live view of an agent for the panel. Optional, purely additive. */
export interface AgentView {
	getMessages(): unknown[];
	/** The system prompt the agent runs with (shown at the top of the transcript). */
	getSystemPrompt?(): string;
	getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined;
	/**
	 * The in-progress assistant message of the current turn, or undefined when idle. Lives only
	 * in the event stream (session.messages gets it at message_end), so the panel seeds it on
	 * switch — otherwise a slow-thinking agent shows no "Thinking..." until its next delta event.
	 */
	getStreamingMessage?(): unknown;
	// Listener receives the full session event; `message` carries streaming deltas
	// (used by the panel for live streaming). Loosely typed to stay SDK-free.
	subscribe(listener: (e: { type: string; message?: unknown; assistantMessageEvent?: unknown }) => void): () => void;
}

/** What an agent is doing right now (only meaningful while `streaming`). */
export type AgentActivity = "thinking" | "writing" | "tool";

/**
 * Terminal reason of an agent's last turn (mirror of pi-ai's StopReason; redeclared here to
 * keep the engine SDK-free). Only the idle-time outcomes matter for the status: "error"
 * (failed after the SDK exhausted its retries) and "length" (output truncated at max tokens).
 * "toolUse" never reaches idle (the agent keeps streaming), "aborted" is covered by halt/kill.
 */
export type StopReason = "stop" | "length" | "toolUse" | "error" | "aborted";

export interface AgentRecord {
	name: string;
	model: string; // "provider/id", display only
	handle: AgentHandle;
	/** Optional live view of transcript/context/events (for the panel). */
	view?: AgentView;
	spawnedBy: string;
	depth: number; // main = 0
	createdAt: number;
	turns: number;
	lastActivity: number;
	streaming: boolean;
	/** System prompt the agent runs with (the spawn prompt, not the infra preamble). Persisted to roster.json so a restart can rebuild the session. */
	systemPrompt?: string;
	/** Absolute path of this agent's session JSONL on disk (undefined for 'main' + in-memory). */
	sessionFile?: string;
	/** Fine-grained phase within a turn (reasoning vs answer text vs tool run). */
	activity?: AgentActivity;
	/** Agent-set semantic status, appended to the system status (in-memory; resets on restart). */
	customStatus?: string;
	/** Absolute target time (epoch ms) for the agent's ETA, rendered as clock time. Set via set_status's etaMinutes; cleared when omitted. In-memory; resets on restart. */
	etaTs?: number;
	/** Tool name while `activity === "tool"`. */
	currentTool?: string;
	/** Terminal reason of the last finished turn; drives the idle-time status (error/truncated). Cleared when a new turn starts. */
	stopReason?: StopReason;
	/**
	 * Set when the swarm was halted (manual /halt or turn-budget) while this agent was
	 * mid-turn. Marks it for re-triggering on resume; survives the agent_end of an
	 * allowed-to-complete turn (setStreaming(false) must NOT clear it). Cleared by resume().
	 */
	halted?: boolean;
	/** Reservation intermediate state: name taken, session still being created. */
	pending?: boolean;
	/** Messages buffered while pending (flushed to the session on attach). */
	buffer?: string[];
	/** Cleanup function (e.g. detach event subscription) — called on kill. */
	dispose?: () => void;
	/** Messages buffered while the swarm is frozen (manual /halt or turn-budget). Flushed on resume. */
	frozenInbox?: string[];
}

export interface Caps {
	maxAgents: number; // excluding 'main'
	maxSpawnDepth: number;
	turnBudget: number; // global across all background agents
}

export type AgentEvent =
	| { type: "spawn"; name: string; by: string; ts: number }
	| { type: "route"; from: string; to: string; preview: string; ts: number }
	| { type: "turn"; name: string; ts: number }
	| { type: "halt"; reason: "manual" | "budget"; ts: number }
	| { type: "resume"; ts: number }
	| { type: "kill"; name: string; ts: number }
	| { type: "blocked"; reason: string; ts: number }
	| { type: "error"; name: string; reason: string; ts: number };

export type CheckResult = { ok: true } | { ok: false; reason: string };

const RESERVED = new Set(["main"]);
const NAME_RE = /^[a-zA-Z0-9_-]+$/;

export class Engine {
	readonly events: AgentEvent[] = [];
	private readonly agents = new Map<string, AgentRecord>();
	private readonly listeners = new Set<(e: AgentEvent) => void>();
	// Graph tracking (in-memory, survives /reload via the singleton, resets on pi restart).
	private readonly messageEdges = new Map<string, Map<string, number>>(); // from -> (to -> count)
	private readonly spawnParent = new Map<string, string>(); // child -> parent (main = root, no entry)
	private frozen = false;
	// Why the swarm is halted; drives the escalation-to-main decision (only "budget" escalates).
	private frozenReason: "manual" | "budget" | undefined;
	private turnsUsed = 0;
	private readonly caps: Caps;

	// Note: no TS parameter properties — Node's strip-only mode (node --test on .ts)
	// does not support them.
	constructor(caps: Caps) {
		this.caps = caps;
	}

	private emit(e: AgentEvent): void {
		this.events.push(e);
		for (const l of this.listeners) l(e);
	}

	subscribe(l: (e: AgentEvent) => void): () => void {
		this.listeners.add(l);
		return () => this.listeners.delete(l);
	}

	has(name: string): boolean {
		return this.agents.has(name);
	}

	get(name: string): AgentRecord | undefined {
		return this.agents.get(name);
	}

	list(): AgentRecord[] {
		return [...this.agents.values()];
	}

	get budget(): { used: number; total: number } {
		return { used: this.turnsUsed, total: this.caps.turnBudget };
	}

	canSpawn(name: string, spawnerDepth: number): CheckResult {
		if (RESERVED.has(name)) return { ok: false, reason: `name '${name}' is reserved` };
		if (!NAME_RE.test(name)) return { ok: false, reason: `invalid name '${name}' (use [a-zA-Z0-9_-])` };
		if (this.agents.has(name)) return { ok: false, reason: `agent '${name}' already exists` };
		const backgroundCount = [...this.agents.values()].filter((a) => a.name !== "main").length;
		if (backgroundCount >= this.caps.maxAgents) {
			return { ok: false, reason: `max agents reached (${this.caps.maxAgents})` };
		}
		if (spawnerDepth + 1 > this.caps.maxSpawnDepth) {
			return { ok: false, reason: `max spawn depth reached (${this.caps.maxSpawnDepth})` };
		}
		return { ok: true };
	}

	addAgent(rec: AgentRecord): void {
		this.agents.set(rec.name, rec);
		this.emit({ type: "spawn", name: rec.name, by: rec.spawnedBy, ts: Date.now() });
	}

	// --- Atomic reservation (prevents spawn/send, duplicate and cap races) ---
	// canSpawn (sync) is separated from the slow session creation by an await;
	// reserve locks the name synchronously, attach fills in the real session afterwards.

	/** Reserves an agent name synchronously. Buffers messages until attach. */
	reserve(name: string, spawnerName: string): CheckResult {
		const spawner = this.agents.get(spawnerName);
		const depth = spawner ? spawner.depth : 0;
		const check = this.canSpawn(name, depth);
		if (!check.ok) return check;
		// Full clean slate for a re-spawned name: drop its old incoming + outgoing edges.
		this.messageEdges.delete(name);
		for (const targets of this.messageEdges.values()) targets.delete(name);
		this.spawnParent.set(name, spawnerName);
		const buffer: string[] = [];
		const record: AgentRecord = {
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
		this.agents.set(name, record);
		this.emit({ type: "spawn", name, by: spawnerName, ts: Date.now() });
		return { ok: true };
	}

	/** Completes a reservation: set the real session data + flush the buffer. */
	attach(
		name: string,
		opts: {
			model: string;
			handle: AgentHandle;
			view?: AgentView;
			dispose?: () => void;
			systemPrompt?: string;
			sessionFile?: string;
		},
	): void {
		const rec = this.agents.get(name);
		if (!rec) return;
		rec.model = opts.model;
		rec.handle = opts.handle;
		rec.view = opts.view;
		rec.dispose = opts.dispose;
		rec.systemPrompt = opts.systemPrompt;
		rec.sessionFile = opts.sessionFile;
		rec.pending = false;
		const buffered = rec.buffer ?? [];
		rec.buffer = undefined;
		for (const t of buffered) void opts.handle.deliver(t);
	}

	/** Release a reservation (session creation failed). */
	release(name: string): void {
		this.agents.delete(name);
	}

	/** Terminate an agent (poison pill): abort its turn, clean up, remove. 'main' is off-limits. */
	kill(name: string): CheckResult {
		if (name === "main") return { ok: false, reason: "cannot kill 'main'" };
		const rec = this.agents.get(name);
		if (!rec) return { ok: false, reason: `unknown agent '${name}'` };
		void rec.handle.abort();
		rec.dispose?.();
		this.agents.delete(name);
		this.emit({ type: "kill", name, ts: Date.now() });
		return { ok: true };
	}

	/** Kill all agents except 'main'. Returns the names of those killed. */
	killAll(): string[] {
		const killed: string[] = [];
		for (const name of [...this.agents.keys()]) {
			if (name === "main") continue;
			if (this.kill(name).ok) killed.push(name);
		}
		return killed;
	}

	isFrozen(): boolean {
		return this.frozen;
	}

	/**
	 * Freeze the swarm. Marks every agent that is currently mid-turn (`streaming`) as
	 * `halted` so resume can re-trigger their interrupted work; idle agents are left alone.
	 * Cause-agnostic: covers manual /halt and the turn-budget path uniformly.
	 */
	halt(reason: "manual" | "budget" = "manual"): void {
		this.frozen = true;
		this.frozenReason = reason;
		for (const rec of this.agents.values()) {
			if (rec.name !== "main" && rec.streaming) rec.halted = true;
		}
		this.emit({ type: "halt", reason, ts: Date.now() });
	}

	resume(): void {
		this.frozen = false;
		this.frozenReason = undefined;
		this.turnsUsed = 0;
		for (const rec of this.agents.values()) rec.halted = false;
		this.emit({ type: "resume", ts: Date.now() });
	}

	async route(
		from: string,
		to: string,
		content: string,
	): Promise<{ ok: true; status: string } | { ok: false; reason: string }> {
		if (this.frozen) {
			const reason = "agents halted (use /unhalt)";
			this.emit({ type: "blocked", reason, ts: Date.now() });
			return { ok: false, reason };
		}
		const target = this.agents.get(to);
		if (!target) return { ok: false, reason: `unknown agent '${to}'` };
		const text = `[message from ${from}]: ${content}`;
		const wasStreaming = target.handle.isStreaming();
		await target.handle.deliver(text);
		target.lastActivity = Date.now();
		// Count the message edge for the relationship graph.
		let targets = this.messageEdges.get(from);
		if (!targets) {
			targets = new Map<string, number>();
			this.messageEdges.set(from, targets);
		}
		targets.set(to, (targets.get(to) ?? 0) + 1);
		const preview = content.length > 60 ? `${content.slice(0, 60)}...` : content;
		this.emit({ type: "route", from, to, preview, ts: Date.now() });
		return { ok: true, status: wasStreaming ? "queued (busy)" : "delivered (woken)" };
	}

	/** Adjacency matrix of message counts: from -> (to -> count). Plain snapshot copy. */
	getMessageMatrix(): Record<string, Record<string, number>> {
		const out: Record<string, Record<string, number>> = {};
		for (const [from, targets] of this.messageEdges) {
			out[from] = Object.fromEntries(targets);
		}
		return out;
	}

	/** Spawn tree as child -> parent. Plain snapshot copy ('main' has no parent). */
	getSpawnTree(): Record<string, string> {
		return Object.fromEntries(this.spawnParent);
	}

	/** Call before every background turn. abort=true => caller must call session.abort(). */
	recordTurnStart(name: string): { abort: boolean; reason?: string } {
		if (this.frozen) {
			return {
				abort: true,
				reason: this.frozenReason === "budget" ? `turn budget exhausted (${this.caps.turnBudget})` : "agents halted",
			};
		}
		this.turnsUsed++;
		const rec = this.agents.get(name);
		if (rec) {
			rec.turns++;
			rec.lastActivity = Date.now();
		}
		this.emit({ type: "turn", name, ts: Date.now() });
		// Freeze-by-blocking: the turn that REACHES the budget is allowed to complete
		// (abort:false). Only subsequent turn_starts hit the frozen guard above and abort.
		// This stops agents at clean turn boundaries instead of cutting an in-flight turn.
		// pi's SDK exposes no "stop after current turn" hook (agent-core shouldStopAfterTurn
		// is internal), so blocking the next turn_start is the closest reachable equivalent.
		if (this.turnsUsed >= this.caps.turnBudget) this.halt("budget");
		return { abort: false };
	}

	/** Report an async failure (e.g. a fire-and-forget delivery turn that later threw). */
	reportError(name: string, reason: string): void {
		// A failed turn may never fire agent_end, so clear streaming here to avoid the
		// status sticking at thinking/writing/tool (setStreaming(false) also resets activity).
		this.setStreaming(name, false);
		// Surface the failure as the idle "error" status (this is the thrown-exception path; the
		// SDK's retry-exhausted path goes through setStopReason at agent_end). Order matters:
		// setStreaming(false) does NOT clear stopReason, so set it after.
		this.setStopReason(name, "error");
		this.emit({ type: "error", name, reason, ts: Date.now() });
	}

	/** Record the terminal reason of an agent's last turn (shown at idle via statusLabel). */
	setStopReason(name: string, reason: StopReason | undefined): void {
		const rec = this.agents.get(name);
		if (rec) rec.stopReason = reason;
	}

	setStreaming(name: string, streaming: boolean): void {
		const rec = this.agents.get(name);
		if (!rec) return;
		rec.streaming = streaming;
		// A new turn supersedes the previous outcome: clear the stale stopReason on turn start.
		if (streaming) rec.stopReason = undefined;
		if (!streaming) {
			// Turn over -> no activity/tool to report.
			rec.activity = undefined;
			rec.currentTool = undefined;
		}
	}

	/**
	 * Set the agent-set semantic status line (empty string clears) plus its optional ETA.
	 * One call fully specifies the visible status: etaTs === undefined clears any prior ETA.
	 */
	setCustomStatus(name: string, status: string | undefined, etaTs?: number): void {
		const rec = this.agents.get(name);
		if (!rec) return;
		rec.customStatus = status || undefined;
		rec.etaTs = etaTs;
	}

	/** Set the fine-grained phase within a turn (thinking/writing/tool). */
	setActivity(name: string, activity: AgentActivity, tool?: string): void {
		const rec = this.agents.get(name);
		if (!rec) return;
		rec.activity = activity;
		rec.currentTool = activity === "tool" ? tool : undefined;
		rec.lastActivity = Date.now();
	}
}

/**
 * Single source of truth for an agent's display status, shared by the agent-facing
 * roster (list_agents) and the TUI panel so the vocabulary stays consistent.
 * spawning = session starting · halted = stopped mid-work by /halt or the turn budget
 * (resume re-triggers it) · thinking = model reasoning · writing = generating answer
 * text · tool:<name> = running a tool · idle = finished its turn, waiting for input ·
 * error = last turn failed after retries exhausted · truncated = output hit max tokens.
 */
export function statusLabel(
	rec: Pick<AgentRecord, "pending" | "streaming" | "activity" | "currentTool" | "halted" | "stopReason">,
): string {
	if (rec.pending) return "spawning";
	if (rec.halted) return "halted";
	if (!rec.streaming) {
		// Idle: surface a noteworthy terminal outcome of the last turn, else plain idle.
		if (rec.stopReason === "error") return "error";
		if (rec.stopReason === "length") return "truncated";
		return "idle";
	}
	if (rec.activity === "tool") return rec.currentTool ? `tool:${rec.currentTool}` : "tool";
	if (rec.activity === "writing") return "writing";
	return "thinking";
}
