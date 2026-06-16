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
import { formatContext, formatRosterRow } from "./panel-logic.ts";
import { createSwarmPanel } from "./panel.ts";
import { createSpawner, type ResolvedModel, type SessionLike } from "./swarm.ts";

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
	type UI = {
		setStatus(key: string, text: string | undefined): void;
		setWidget(key: string, content: string[] | undefined, opts?: { placement?: "aboveEditor" | "belowEditor" }): void;
	};
	let ui: UI | undefined;
	// Vordergrund-ctx für getContextUsage der user-Zeile (live gelesen).
	type CtxRef = { getContextUsage(): { tokens: number | null; contextWindow: number; percent: number | null } | undefined };
	let foregroundCtx: CtxRef | undefined;
	type ModelLike = { provider: string; id: string };
	let cwd = process.cwd();
	let foregroundModel: ModelLike | undefined; // aktuelles Vordergrund-Modell (für Vererbung an Actors)
	let foregroundStreaming = false;

	// Modell aus jedem Vordergrund-Handler-ctx erfassen (zuverlässiger als model_select allein).
	const captureForegroundModel = (m: ModelLike | undefined) => {
		if (!m) return;
		foregroundModel = { provider: m.provider, id: m.id };
		const u = engine.get("user");
		if (u) u.model = `${m.provider}/${m.id}`;
	};

	const updateStatus = () => {
		if (!ui) return;
		const actors = engine.list();
		const running = actors.filter((a) => a.streaming).length;
		const { used, total } = engine.budget;
		ui.setStatus("swarm", formatStatus(actors.length, running, used, total));
		// Permanente Roster-Anzeige über dem Editor (plan-mode-Muster, kein Overlay).
		const rosterLines = actors.map((a) =>
			formatRosterRow({ name: a.name, context: formatContext(a.view?.getContextUsage()), active: a.streaming }, false, 80),
		);
		ui.setWidget("swarm-roster", rosterLines.length ? rosterLines : undefined);
	};

	// Status bei jedem Engine-Event aktualisieren.
	engine.subscribe(() => updateStatus());

	const resolveModel = (ref: string | undefined): ResolvedModel | undefined => {
		if (ref && ref.includes("/")) {
			const slash = ref.indexOf("/");
			const model = modelRegistry.find(ref.slice(0, slash), ref.slice(slash + 1));
			if (model) return { provider: model.provider, id: model.id, model };
		}
		// Fallback: aktuelles Vordergrund-Modell (deckt Vererbung + den "(foreground)"-Platzhalter ab).
		if (foregroundModel) {
			const model = modelRegistry.find(foregroundModel.provider, foregroundModel.id);
			if (model) return { provider: foregroundModel.provider, id: foregroundModel.id, model };
		}
		return undefined;
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

	// SDK-Adapter: erzeugt eine isolierte Hintergrund-Actor-Session.
	const createSession = async (spec: {
		name: string;
		role: string;
		model: unknown;
		tools?: string[];
	}): Promise<SessionLike> => {
		const loader = new DefaultResourceLoader({
			cwd,
			agentDir: blankAgentDir,
			systemPromptOverride: () => actorSystemPrompt(spec.name, spec.role),
		});
		await loader.reload();

		const toolAllowlist = spec.tools ? [...spec.tools, "spawn_agent", "send_message", "list_agents"] : undefined;

		const { session } = await createAgentSession({
			cwd,
			model: spec.model as Parameters<typeof createAgentSession>[0]["model"],
			authStorage,
			modelRegistry,
			customTools: makeActorTools(spec.name),
			...(toolAllowlist ? { tools: toolAllowlist } : {}),
			resourceLoader: loader,
			sessionManager: SessionManager.inMemory(cwd),
		});
		return session;
	};

	const { spawnActor } = createSpawner({ engine, resolveModel, createSession, onActivity: updateStatus });

	// Foreground-Modell erfassen (für Vererbung an gespawnte Actors).
	pi.on("model_select", (event) => {
		captureForegroundModel(event.model);
	});

	// Foreground-Streaming-Flag für Statusanzeige + Modell erfassen.
	pi.on("agent_start", (_event, ctx) => {
		captureForegroundModel(ctx.model);
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
		foregroundCtx = ctx;
		captureForegroundModel(ctx.model);
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
				model: foregroundModel ? `${foregroundModel.provider}/${foregroundModel.id}` : "(foreground)",
				handle: userHandle,
				spawnedBy: "user",
				depth: 0,
				createdAt: Date.now(),
				turns: 0,
				lastActivity: Date.now(),
				streaming: false,
				view: {
					getMessages: () => [], // user-Transcript = Haupt-Chat (nicht gespiegelt)
					getContextUsage: () => foregroundCtx?.getContextUsage(),
					subscribe: () => () => {},
				},
			});
		}
		updateStatus();
	});

	// Vordergrund-Tools für 'user' registrieren.
	for (const tool of makeActorTools("user")) {
		pi.registerTool(tool);
	}

	pi.registerCommand("halt", {
		description: "Freeze the whole actor swarm (stop new turns, abort running background actors).",
		handler: async (_args, ctx) => {
			engine.halt();
			for (const a of engine.list()) {
				if (a.name !== "user") void a.handle.abort();
			}
			ctx.ui.notify("Swarm halted. Use /unhalt to continue.", "warning");
			updateStatus();
		},
	});

	// Hinweis: nicht "resume" — das kollidiert mit pi's eingebautem /resume (Session fortsetzen).
	pi.registerCommand("unhalt", {
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

	// /swarm öffnet das Panel als Vollbild-Takeover (kein Overlay — fror ein).
	pi.registerCommand("swarm", {
		description: "Open the swarm panel (Esc to close)",
		handler: async (_args, ctx) => {
			await ctx.ui.custom<void>((tui, theme, _kb, done) =>
				createSwarmPanel({ engine, route: (to, content) => void engine.route("user", to, content) }, tui, theme, done),
			);
		},
	});
}
