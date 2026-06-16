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
import { formatFeedLines, formatKillResult, formatMulticastResult, formatSnapshot, normalizeTargets } from "./feed.ts";
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

// Zustellung an den 'user'-Actor läuft über diese globalThis-Indirection, NICHT über ein
// gecapturetes `pi`. Der Engine-Singleton überlebt /reload und Session-Replacement, ein
// gecapturetes `pi` wird dabei aber dauerhaft stale (pi loader: state.staleMessage ??= ...,
// wird nie zurückgesetzt). Jede frisch geladene Instanz überschreibt den Sink mit ihrem
// eigenen lebenden pi.sendUserMessage, sodass der gespeicherte user-Handle nie ein totes
// pi aufruft.
const USER_SINK_KEY = "__actorSwarmUserSink_v1";
type UserSink = (text: string) => void;
function setUserSink(sink: UserSink): void {
	(globalThis as Record<string, unknown>)[USER_SINK_KEY] = sink;
}
function deliverToUser(text: string): void {
	const sink = (globalThis as Record<string, unknown>)[USER_SINK_KEY] as UserSink | undefined;
	if (!sink) throw new Error("no live foreground session to deliver to 'user'");
	sink(text);
}

function actorSystemPrompt(name: string, systemPrompt: string): string {
	return [
		`You are agent "${name}" in a multi-agent swarm.`,
		"You can talk to other agents with these tools:",
		"- spawn_agent({name, systemPrompt, model?, tools?, message?}): create a new agent (message = optional first task).",
		"- send_message({to, content}): to is an agent name OR a list of names; fire-and-forget (e.g. 'user').",
		"- list_agents(): see who exists.",
		"- kill_agent({name}): terminate an agent or a list of agents (you cannot kill 'user').",
		"Messages you receive are prefixed with [message from <sender>].",
		"To reply, use send_message back to that sender.",
		"",
		systemPrompt,
	].join("\n");
}

export default function actorSwarm(pi: ExtensionAPI) {
	const engine = getEngine();

	// Diese (frisch geladene) Instanz besitzt ab jetzt die user-Zustellung mit ihrem
	// lebenden pi — ersetzt einen ggf. veralteten Sink einer vorherigen Instanz.
	setUserSink((text) => pi.sendUserMessage(text, { deliverAs: "followUp" }));

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
		theme: { fg(color: string, s: string): string; bg(color: string, s: string): string };
	};
	let ui: UI | undefined;
	// user-Kontext als WERT cachen — nie den ctx selbst halten (der wird nach
	// Turn/Reload stale; ein gecachter ctx-Aufruf crasht pi mit "stale ctx").
	type Usage = { tokens: number | null; contextWindow: number; percent: number | null };
	let userContextUsage: Usage | undefined;
	const captureUserContext = (c: { getContextUsage(): Usage | undefined }) => {
		try {
			userContextUsage = c.getContextUsage();
		} catch {
			/* ctx stale -> ignorieren, wird beim nächsten Handler aufgefrischt */
		}
	};
	type ModelLike = { provider: string; id: string };
	let cwd = process.cwd();
	let foregroundModel: ModelLike | undefined; // aktuelles Vordergrund-Modell (für Vererbung an Actors)
	let foregroundStreaming = false;
	// Solange das /swarm-Panel offen ist, das persistente Roster ausblenden (sonst doppelt).
	let panelOpen = false;

	// Modell aus jedem Vordergrund-Handler-ctx erfassen (zuverlässiger als model_select allein).
	const captureForegroundModel = (m: ModelLike | undefined) => {
		if (!m) return;
		foregroundModel = { provider: m.provider, id: m.id };
		const u = engine.get("user");
		if (u) u.model = `${m.provider}/${m.id}`;
	};

	const updateStatus = () => {
		if (!ui) return;
		try {
			const actors = engine.list();
			// Footer-Status entfällt — Anzahl/running/budget stehen im /swarm-Panel-Header.
			// Permanente Roster-Anzeige über dem Editor (plan-mode-Muster, kein Overlay).
			// Nur zeigen, wenn mindestens ein Hintergrund-Actor existiert (nur 'user' allein
			// ist redundant) und das /swarm-Panel nicht ohnehin offen ist.
			// Nur Hintergrund-Actors anzeigen ('user' = der Chat selbst, redundant).
			const background = actors.filter((a) => a.name !== "user");
			const theme = ui.theme;
			const styler = (label: string, active: boolean) =>
				active ? theme.bg("toolSuccessBg", label) : theme.fg("dim", label);
			const rosterLines = background.map((a) =>
				formatRosterRow(
					{ name: a.name, context: formatContext(a.view?.getContextUsage()), active: a.streaming },
					false,
					80,
					styler,
				),
			);
			const haltLine = engine.isFrozen()
				? theme.bg("toolPendingBg", " ⏸ agents HALTED — /unhalt to resume ".padEnd(80))
				: theme.bg("selectedBg", " ▶ running ");
			ui.setWidget(
				"swarm-roster",
				panelOpen || background.length === 0 ? undefined : [...rosterLines, haltLine],
			);
		} catch {
			/* ui aus einem stale ctx -> diesen Tick überspringen, frischt beim nächsten Handler auf */
		}
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
			description:
				"Create a new agent with a system prompt; optionally deliver a first message. It can then be messaged by name.",
			parameters: Type.Object({
				name: Type.String({ description: "Unique agent name ([a-zA-Z0-9_-])" }),
				systemPrompt: Type.String({ description: "System prompt defining the actor's behavior" }),
				model: Type.Optional(Type.String({ description: "provider/id; default: inherited" })),
				tools: Type.Optional(Type.Array(Type.String(), { description: "Built-in tool allowlist" })),
				message: Type.Optional(
					Type.String({ description: "Optional first message delivered to the new actor right after spawn" }),
				),
			}),
			execute: async (_id, args) => {
				const res = await spawnActor(args, selfName);
				return { content: [{ type: "text", text: res.msg }], details: {} };
			},
		},
		{
			name: "send_message",
			label: "Send Message",
			description: "Fire-and-forget message to one agent or a list of agents (e.g. 'user'). Returns immediately.",
			parameters: Type.Object({
				to: Type.Union([Type.String(), Type.Array(Type.String())], {
					description: "Target agent name, or a list of names for multicast",
				}),
				content: Type.String({ description: "Message content" }),
			}),
			execute: async (_id, args) => {
				const targets = normalizeTargets(args.to);
				const results = [];
				for (const t of targets) {
					const r = await engine.route(selfName, t, args.content);
					results.push(r.ok ? { target: t, ok: true } : { target: t, ok: false, reason: r.reason });
				}
				return { content: [{ type: "text", text: formatMulticastResult(results) }], details: {} };
			},
		},
		{
			name: "list_agents",
			label: "List Agents",
			description: "List all agents and their status.",
			parameters: Type.Object({}),
			execute: async () => {
				const { used, total } = engine.budget;
				return { content: [{ type: "text", text: formatSnapshot(engine.list(), used, total) }], details: {} };
			},
		},
		{
			name: "kill_agent",
			label: "Kill Agent",
			description: "Terminate one agent or a list of agents. 'user' cannot be killed.",
			parameters: Type.Object({
				name: Type.Union([Type.String(), Type.Array(Type.String())], {
					description: "Agent name, or a list of names to terminate",
				}),
			}),
			execute: async (_id, args) => {
				const targets = normalizeTargets(args.name);
				const results = targets.map((t) => {
					const r = engine.kill(t);
					return r.ok ? { target: t, ok: true } : { target: t, ok: false, reason: r.reason };
				});
				return { content: [{ type: "text", text: formatKillResult(results) }], details: {} };
			},
		},
	];

	// SDK-Adapter: erzeugt eine isolierte Hintergrund-Actor-Session.
	const createSession = async (spec: {
		name: string;
		systemPrompt: string;
		model: unknown;
		tools?: string[];
	}): Promise<SessionLike> => {
		const loader = new DefaultResourceLoader({
			cwd,
			agentDir: blankAgentDir,
			systemPromptOverride: () => actorSystemPrompt(spec.name, spec.systemPrompt),
		});
		await loader.reload();

		const toolAllowlist = spec.tools
			? [...spec.tools, "spawn_agent", "send_message", "list_agents", "kill_agent"]
			: undefined;

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
		ui = ctx.ui;
		captureForegroundModel(ctx.model);
		captureUserContext(ctx);
		foregroundStreaming = true;
		engine.setStreaming("user", true);
		updateStatus();
	});
	pi.on("agent_end", (_event, ctx) => {
		ui = ctx.ui;
		captureUserContext(ctx);
		foregroundStreaming = false;
		engine.setStreaming("user", false);
		updateStatus();
	});

	// 'user'-Actor registrieren (Vordergrund). Zustellung an user via pi.sendUserMessage.
	pi.on("session_start", (_event, ctx) => {
		cwd = ctx.cwd;
		ui = ctx.ui;
		ctx.ui.setStatus("swarm", undefined); // Footer-Status wird nicht mehr genutzt (Infos im Panel)
		captureUserContext(ctx);
		captureForegroundModel(ctx.model);
		if (!engine.has("user")) {
			const userHandle: ActorHandle = {
				// über die globalThis-Indirection, damit der Singleton-Handle nie ein stale pi nutzt.
				deliver: async (text) => {
					deliverToUser(text);
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
					getContextUsage: () => userContextUsage, // gecachter WERT, kein stale ctx
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
		description: "Freeze the whole agent swarm (stop new turns, abort running background agents).",
		handler: async (_args, ctx) => {
			engine.halt();
			for (const a of engine.list()) {
				if (a.name !== "user") void a.handle.abort();
			}
			ctx.ui.notify("Agents halted. Use /unhalt to continue.", "warning");
			updateStatus();
		},
	});

	// Hinweis: nicht "resume" — das kollidiert mit pi's eingebautem /resume (Session fortsetzen).
	pi.registerCommand("unhalt", {
		description: "Resume halted agents and reset the turn budget.",
		handler: async (_args, ctx) => {
			engine.resume();
			ctx.ui.notify("Agents resumed; turn budget reset.", "info");
			updateStatus();
		},
	});

	pi.registerCommand("killall", {
		description: "Terminate all agents (except 'user').",
		handler: async (_args, ctx) => {
			const killed = engine.killAll();
			ctx.ui.notify(killed.length ? `Killed ${killed.length} agent(s): ${killed.join(", ")}` : "No agents to kill.", "info");
			updateStatus();
		},
	});

	pi.registerCommand("feed", {
		description: "Show the agent activity log (last 40 events).",
		handler: async (_args, ctx) => {
			const lines = formatFeedLines(engine.events).slice(-40);
			ctx.ui.notify(lines.length ? lines.join("\n") : "(no activity yet)", "info");
		},
	});

	// /agents öffnet das Panel als Vollbild-Takeover (kein Overlay — fror ein).
	pi.registerCommand("agents", {
		description: "Open the agents panel (Esc to close)",
		handler: async (_args, ctx) => {
			ui = ctx.ui;
			panelOpen = true;
			updateStatus(); // redundantes persistentes Roster ausblenden
			try {
				await ctx.ui.custom<void>((tui, theme, _kb, done) =>
					createSwarmPanel({ engine, cwd, route: (to, content) => void engine.route("user", to, content) }, tui, theme, done),
				);
			} finally {
				panelOpen = false;
				updateStatus(); // persistentes Roster wieder einblenden
			}
		},
	});
}
