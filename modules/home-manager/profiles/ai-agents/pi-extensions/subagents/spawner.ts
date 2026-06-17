/**
 * Subagents orchestration — SDK-free, so it stays headless-testable.
 * index.ts injects the real pi/SDK adapters (createSession, resolveModel, ...).
 * Design: docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md
 */
import type { AgentHandle, Engine } from "./engine.ts";

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
	/** Create an isolated background agent session (SDK adapter in index.ts). */
	createSession: (spec: {
		name: string;
		systemPrompt: string;
		spawnedBy: string;
		model: unknown;
	}) => Promise<SessionLike>;
	/** Called after every relevant activity (e.g. refresh the status footer). */
	onActivity?: () => void;
}

export interface Spawner {
	spawnAgent: (spec: SpawnSpec, spawnerName: string) => Promise<{ ok: boolean; msg: string }>;
}

export function createSpawner(deps: SpawnerDeps): Spawner {
	const { engine, resolveModel, createSession, onActivity } = deps;

	// Subscribe to a background session's lifecycle to enforce the turn budget and
	// track streaming state.
	const subscribeBackground = (name: string, session: SessionLike): (() => void) => {
		return session.subscribe((ev) => {
			if (ev.type === "turn_start") {
				const r = engine.recordTurnStart(name);
				if (r.abort) void session.abort();
			}
			if (ev.type === "agent_start" || ev.type === "message_start") engine.setStreaming(name, true);
			if (ev.type === "agent_end") engine.setStreaming(name, false);
			onActivity?.();
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
			return { ok: false, msg: `error: unknown model '${inheritRef ?? "(none)"}'` };
		}

		// 2) Slow session creation (await). A concurrent send_message buffers meanwhile.
		let session: SessionLike;
		try {
			session = await createSession({
				name: spec.name,
				systemPrompt: spec.systemPrompt,
				spawnedBy: spawnerName,
				model: resolved.model,
			});
		} catch (e) {
			engine.release(spec.name);
			return { ok: false, msg: `error: failed to start '${spec.name}': ${e instanceof Error ? e.message : String(e)}` };
		}

		const handle: AgentHandle = {
			// Fire-and-forget: sendUserMessage internally awaits prompt(), which only resolves
			// when the whole turn completes. Awaiting it would block the caller (e.g. the
			// spawn_agent tool) until the target agent finishes. Kick the turn and return; a
			// late failure surfaces as an engine error event (visible in /feed + panel).
			// deliverAs "steer": if the target is mid-turn, deliver at the next turn boundary
			// (after the current tool calls, before the next LLM call) instead of waiting for it
			// to fully stop — as direct as possible without aborting in-progress work. Combined
			// with setSteeringMode("all") (set at spawn) so several queued messages all arrive at
			// that boundary. Idle targets start a turn immediately regardless of deliverAs.
			deliver: async (text) => {
				void Promise.resolve(session.sendUserMessage(text, { deliverAs: "steer" })).catch((e) =>
					engine.reportError(spec.name, e instanceof Error ? e.message : String(e)),
				);
			},
			abort: async () => {
				await session.abort();
			},
			isStreaming: () => session.isStreaming,
		};

		// 3) Complete the reservation (flushes any buffered messages to the session).
		engine.attach(spec.name, {
			model: `${resolved.provider}/${resolved.id}`,
			handle,
			view: {
				getMessages: () => session.messages,
				// Only the prompt passed at spawn time — not the full session.systemPrompt
				// (which also contains the infra preamble, AGENTS.md, skills, etc.).
				getSystemPrompt: () => spec.systemPrompt,
				getContextUsage: () => session.getContextUsage(),
				subscribe: (l) => session.subscribe(l),
			},
			// Clean up on kill: detach the background event subscription.
			dispose: subscribeBackground(spec.name, session),
		});

		// 4) Deliver the optional first message atomically (no race; the agent is registered).
		let sent = "";
		if (spec.message) {
			const r = await engine.route(spawnerName, spec.name, spec.message);
			sent = r.ok ? " + sent initial message" : ` (initial message NOT delivered: ${r.reason})`;
		}
		return { ok: true, msg: `spawned '${spec.name}' (model ${resolved.provider}/${resolved.id})${sent}` };
	};

	return { spawnAgent };
}
