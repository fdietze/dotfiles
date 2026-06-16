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
	readonly systemPrompt: string;
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
	systemPrompt: string;
	model?: string;
	tools?: string[];
	/** Optionale Startnachricht: nach dem Spawn atomar an den neuen Actor zugestellt. */
	message?: string;
}

export interface SpawnerDeps {
	engine: Engine;
	/** "provider/id" oder undefined (=> erben) auflösen; undefined wenn unbekannt. */
	resolveModel: (ref: string | undefined) => ResolvedModel | undefined;
	/** Eine isolierte Hintergrund-Actor-Session erzeugen (SDK-Adapter in index.ts). */
	createSession: (spec: { name: string; systemPrompt: string; model: unknown; tools?: string[] }) => Promise<SessionLike>;
	/** Nach jeder relevanten Aktivität aufrufen (z.B. Status-Footer aktualisieren). */
	onActivity?: () => void;
}

export interface Spawner {
	spawnActor: (spec: SpawnSpec, spawnerName: string) => Promise<{ ok: boolean; msg: string }>;
}

export function createSpawner(deps: SpawnerDeps): Spawner {
	const { engine, resolveModel, createSession, onActivity } = deps;

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

	const spawnActor = async (spec: SpawnSpec, spawnerName: string): Promise<{ ok: boolean; msg: string }> => {
		const inheritRef = spec.model ?? engine.get(spawnerName)?.model;

		// 1) Namen synchron reservieren (atomar: Duplikat/Cap/Tiefe) — schließt Races.
		const reserved = engine.reserve(spec.name, spawnerName);
		if (!reserved.ok) return { ok: false, msg: `error: ${reserved.reason}` };

		const resolved = resolveModel(inheritRef);
		if (!resolved) {
			engine.release(spec.name);
			return { ok: false, msg: `error: unknown model '${inheritRef ?? "(none)"}'` };
		}

		// 2) Langsame Session-Erstellung (await). Ein paralleles send_message puffert solange.
		let session: SessionLike;
		try {
			session = await createSession({
				name: spec.name,
				systemPrompt: spec.systemPrompt,
				model: resolved.model,
				tools: spec.tools,
			});
		} catch (e) {
			engine.release(spec.name);
			return { ok: false, msg: `error: failed to start '${spec.name}': ${e instanceof Error ? e.message : String(e)}` };
		}

		const handle: ActorHandle = {
			deliver: async (text) => {
				await session.sendUserMessage(text, { deliverAs: "followUp" });
			},
			abort: async () => {
				await session.abort();
			},
			isStreaming: () => session.isStreaming,
		};

		// 3) Reservierung abschließen (flusht ggf. gepufferte Nachrichten an die Session).
		engine.attach(spec.name, {
			model: `${resolved.provider}/${resolved.id}`,
			handle,
			view: {
				getMessages: () => session.messages,
				getSystemPrompt: () => session.systemPrompt,
				getContextUsage: () => session.getContextUsage(),
				subscribe: (l) => session.subscribe(l),
			},
			// Beim Kill aufräumen: Background-Event-Subscription lösen.
			dispose: subscribeBackground(spec.name, session),
		});

		// 4) Optionale Startnachricht atomar zustellen (kein Race, da Actor bereits registriert).
		let sent = "";
		if (spec.message) {
			const r = await engine.route(spawnerName, spec.name, spec.message);
			sent = r.ok ? " + sent initial message" : ` (initial message NOT delivered: ${r.reason})`;
		}
		return { ok: true, msg: `spawned '${spec.name}' (model ${resolved.provider}/${resolved.id})${sent}` };
	};

	return { spawnActor };
}
