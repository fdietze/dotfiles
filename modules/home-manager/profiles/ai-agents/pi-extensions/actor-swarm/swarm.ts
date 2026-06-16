/**
 * Orchestrierung des Actor-Swarms — SDK-frei, damit headless testbar.
 * index.ts injiziert die echten pi/SDK-Adapter (createSession, resolveModel, ...).
 * Design: docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md
 */
import type { ActorHandle, Engine } from "./engine.ts";

/** Minimaler Ausschnitt einer AgentSession, den der Swarm braucht. */
export interface SessionLike {
	sendUserMessage(text: string, options?: { deliverAs?: "steer" | "followUp" }): Promise<void> | void;
	abort(): Promise<void> | void;
	readonly isStreaming: boolean;
	subscribe(listener: (e: { type: string }) => void): () => void;
	readonly messages: unknown[];
	getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined;
}

/** Aufgelöstes Modell: provider/id zur Anzeige + opakes SDK-Modellobjekt für createSession. */
export interface ResolvedModel {
	provider: string;
	id: string;
	model: unknown;
}

export interface SpawnSpec {
	name: string;
	role: string;
	model?: string;
	tools?: string[];
}

export interface SpawnerDeps {
	engine: Engine;
	/** "provider/id" oder undefined (=> erben) auflösen; undefined wenn unbekannt. */
	resolveModel: (ref: string | undefined) => ResolvedModel | undefined;
	/** Eine isolierte Hintergrund-Actor-Session erzeugen (SDK-Adapter in index.ts). */
	createSession: (spec: { name: string; role: string; model: unknown; tools?: string[] }) => Promise<SessionLike>;
	/** Nach jeder relevanten Aktivität aufrufen (z.B. Status-Footer aktualisieren). */
	onActivity?: () => void;
}

export interface Spawner {
	spawnActor: (spec: SpawnSpec, spawnerName: string) => Promise<{ ok: boolean; msg: string }>;
}

export function createSpawner(deps: SpawnerDeps): Spawner {
	const { engine, resolveModel, createSession, onActivity } = deps;

	const subscribeBackground = (name: string, session: SessionLike) => {
		session.subscribe((ev) => {
			if (ev.type === "turn_start") {
				const r = engine.recordTurnStart(name);
				if (r.abort) void session.abort();
			}
			if (ev.type === "agent_start" || ev.type === "message_start") engine.setStreaming(name, true);
			if (ev.type === "agent_end") engine.setStreaming(name, false);
			onActivity?.();
		});
	};

	const spawnActor = async (spec: SpawnSpec, spawnerName: string): Promise<{ ok: boolean; msg: string }> => {
		const spawner = engine.get(spawnerName);
		const depth = spawner ? spawner.depth : 0;
		const check = engine.canSpawn(spec.name, depth);
		if (!check.ok) return { ok: false, msg: `error: ${check.reason}` };

		const inheritRef = spec.model ?? spawner?.model;
		const resolved = resolveModel(inheritRef);
		if (!resolved) return { ok: false, msg: `error: unknown model '${inheritRef ?? "(none)"}'` };

		const session = await createSession({
			name: spec.name,
			role: spec.role,
			model: resolved.model,
			tools: spec.tools,
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
			model: `${resolved.provider}/${resolved.id}`,
			handle,
			spawnedBy: spawnerName,
			depth: depth + 1,
			createdAt: Date.now(),
			turns: 0,
			lastActivity: Date.now(),
			streaming: false,
			view: {
				getMessages: () => session.messages,
				getContextUsage: () => session.getContextUsage(),
				subscribe: (l) => session.subscribe(l),
			},
		});
		subscribeBackground(spec.name, session);
		return { ok: true, msg: `spawned '${spec.name}' (model ${resolved.provider}/${resolved.id})` };
	};

	return { spawnActor };
}
