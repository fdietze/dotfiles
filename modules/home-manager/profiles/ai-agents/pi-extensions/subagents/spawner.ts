/**
 * Subagents orchestration — SDK-free, so it stays headless-testable.
 * index.ts injects the real pi/SDK adapters (createSession, resolveModel, ...).
 * Design: docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md
 */
import type { AgentHandle, AgentView, Engine, StopReason } from "./engine.ts";

/** Terminal stopReason of the last assistant message in a transcript (undefined if none). */
function lastStopReason(messages: unknown[]): StopReason | undefined {
	for (let i = messages.length - 1; i >= 0; i--) {
		const m = messages[i] as { role?: string; stopReason?: StopReason };
		if (m.role === "assistant") return m.stopReason;
	}
	return undefined;
}

/** Minimal slice of an AgentSession that the orchestration needs. */
export interface SessionLike {
	sendUserMessage(text: string, options?: { deliverAs?: "steer" | "followUp" }): Promise<void> | void;
	abort(): Promise<void> | void;
	readonly isStreaming: boolean;
	subscribe(listener: (e: { type: string; message?: unknown; assistantMessageEvent?: unknown }) => void): () => void;
	readonly messages: unknown[];
	getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined;
}

/** Resolved model: provider/id for display + opaque SDK model object for createSession. */
export interface ResolvedModel {
	provider: string;
	id: string;
	model: unknown;
}

export interface SpawnSpec {
	name: string;
	systemPrompt: string;
	model?: string;
	/** Optional first message: delivered atomically to the new agent right after spawn. */
	message?: string;
}

export interface SpawnerDeps {
	engine: Engine;
	/** Resolve "provider/id" or undefined (=> inherit); undefined if unknown. */
	resolveModel: (ref: string | undefined) => ResolvedModel | undefined;
	/** Available models as "provider/id" (auth configured) — listed in the unknown-model error
	 * so a bad overrideModel self-corrects in one bounce instead of hallucinating again. */
	listAvailableModels?: () => string[];
	/**
	 * Create an isolated background agent session (SDK adapter in index.ts).
	 * Returns the live session plus its on-disk JSONL path (for the persistence roster;
	 * undefined for in-memory sessions).
	 */
	createSession: (spec: {
		name: string;
		systemPrompt: string;
		spawnedBy: string;
		model: unknown;
	}) => Promise<{ session: SessionLike; sessionFile?: string }>;
	/** Called after every relevant activity (e.g. refresh the status footer). */
	onActivity?: () => void;
}

/** Metadata to re-register an agent from a rehydrated (disk-loaded) session on restart. */
export interface RestoreSpec {
	name: string;
	spawnedBy: string;
	depth: number;
	model: string; // "provider/id" display string
	systemPrompt: string;
	sessionFile: string;
	session: SessionLike;
	/** Derived from the transcript tail: true => resume re-triggers it; false => idle. */
	halted: boolean;
}

export interface Spawner {
	spawnAgent: (spec: SpawnSpec, spawnerName: string) => Promise<{ ok: boolean; msg: string }>;
	/** Re-register an agent from a restored session (used by restart resume). */
	restoreAgent: (spec: RestoreSpec) => void;
}

export function createSpawner(deps: SpawnerDeps): Spawner {
	const { engine, resolveModel, createSession, onActivity, listAvailableModels } = deps;

	// Subscribe to a background session's lifecycle to enforce the turn budget and
	// track streaming state.
	const subscribeBackground = (name: string, session: SessionLike): (() => void) => {
		return session.subscribe((ev) => {
			if (ev.type === "turn_start") {
				const r = engine.recordTurnStart(name);
				if (r.abort) void session.abort();
			}
			if (ev.type === "agent_start" || ev.type === "message_start") {
				engine.setStreaming(name, true);
				engine.setActivity(name, "thinking");
			}
			// Refine the phase from streaming sub-events: reasoning vs answer text.
			if (ev.type === "message_update") {
				const sub = (ev.assistantMessageEvent as { type?: string } | undefined)?.type;
				if (sub === "thinking_start") engine.setActivity(name, "thinking");
				else if (sub === "text_start" || sub === "toolcall_start") engine.setActivity(name, "writing");
			}
			if (ev.type === "tool_execution_start")
				engine.setActivity(name, "tool", (ev as { toolName?: string }).toolName);
			if (ev.type === "agent_end") {
				engine.setStreaming(name, false);
				// Surface the turn's terminal outcome at idle (error after retries / truncated).
				engine.setStopReason(name, lastStopReason(session.messages));
			}
			onActivity?.();
		});
	};

	// Wire a live session into engine plumbing: the message handle, the panel view, and the
	// lifecycle subscription (turn budget + streaming). Shared by fresh spawn and restore so
	// both paths behave identically.
	const wire = (name: string, session: SessionLike, systemPrompt: string): { handle: AgentHandle; view: AgentView; dispose: () => void } => {
		const handle: AgentHandle = {
			// Fire-and-forget: sendUserMessage internally awaits prompt(), which only resolves
			// when the whole turn completes. Awaiting it would block the caller (e.g. the
			// spawn_agent tool) until the target agent finishes. Kick the turn and return; a
			// late failure surfaces as an engine error event (visible in /feed + panel).
			// deliverAs "steer": if the target is mid-turn, deliver at the next turn boundary
			// (after the current tool calls, before the next LLM call) instead of waiting for it
			// to fully stop. Combined with setSteeringMode("all") (set at spawn) so several queued
			// messages all arrive at that boundary. Idle targets start a turn immediately.
			deliver: async (text) => {
				void Promise.resolve(session.sendUserMessage(text, { deliverAs: "steer" })).catch((e) =>
					engine.reportError(name, e instanceof Error ? e.message : String(e)),
				);
			},
			abort: async () => {
				await session.abort();
			},
			isStreaming: () => session.isStreaming,
		};
		const view: AgentView = {
			getMessages: () => session.messages,
			// Only the spawn prompt — not the full session.systemPrompt (infra preamble, AGENTS.md,
			// skills, etc.).
			getSystemPrompt: () => systemPrompt,
			getContextUsage: () => session.getContextUsage(),
			subscribe: (l) => session.subscribe(l),
		};
		return { handle, view, dispose: subscribeBackground(name, session) };
	};

	const restoreAgent = (spec: RestoreSpec): void => {
		const { handle, view, dispose } = wire(spec.name, spec.session, spec.systemPrompt);
		engine.addAgent({
			name: spec.name,
			model: spec.model,
			handle,
			view,
			dispose,
			systemPrompt: spec.systemPrompt,
			sessionFile: spec.sessionFile,
			spawnedBy: spec.spawnedBy,
			depth: spec.depth,
			createdAt: Date.now(),
			turns: 0,
			lastActivity: Date.now(),
			streaming: false,
			halted: spec.halted,
		});
	};

	const spawnAgent = async (spec: SpawnSpec, spawnerName: string): Promise<{ ok: boolean; msg: string }> => {
		const inheritRef = spec.model ?? engine.get(spawnerName)?.model;

		// 1) Reserve the name synchronously (atomic: duplicate/cap/depth) — closes races.
		const reserved = engine.reserve(spec.name, spawnerName);
		if (!reserved.ok) return { ok: false, msg: `error: ${reserved.reason}` };

		const resolved = resolveModel(inheritRef);
		if (!resolved) {
			engine.release(spec.name);
			const avail = listAvailableModels?.() ?? [];
			const hint = avail.length ? `; available: ${avail.join(", ")}` : "";
			return { ok: false, msg: `error: unknown model '${inheritRef ?? "(none)"}'${hint}` };
		}

		// 2) Slow session creation (await). A concurrent send_message buffers meanwhile.
		let session: SessionLike;
		let sessionFile: string | undefined;
		try {
			({ session, sessionFile } = await createSession({
				name: spec.name,
				systemPrompt: spec.systemPrompt,
				spawnedBy: spawnerName,
				model: resolved.model,
			}));
		} catch (e) {
			engine.release(spec.name);
			return { ok: false, msg: `error: failed to start '${spec.name}': ${e instanceof Error ? e.message : String(e)}` };
		}

		// 3) Complete the reservation (flushes any buffered messages to the session).
		const { handle, view, dispose } = wire(spec.name, session, spec.systemPrompt);
		engine.attach(spec.name, {
			model: `${resolved.provider}/${resolved.id}`,
			handle,
			view,
			// Clean up on kill: detach the background event subscription.
			dispose,
			// Persisted to roster.json so a restart can rebuild this agent.
			systemPrompt: spec.systemPrompt,
			sessionFile,
		});

		// 4) Deliver the optional first message atomically (no race; the agent is registered).
		let sent = "";
		if (spec.message) {
			const r = await engine.route(spawnerName, spec.name, spec.message);
			sent = r.ok ? " + sent initial message" : ` (initial message NOT delivered: ${r.reason})`;
		}
		return { ok: true, msg: `spawned '${spec.name}' (model ${resolved.provider}/${resolved.id})${sent}` };
	};

	return { spawnAgent, restoreAgent };
}
