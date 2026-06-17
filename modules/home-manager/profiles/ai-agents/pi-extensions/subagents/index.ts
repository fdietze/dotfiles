/**
 * Subagents pi extension — foreground entry.
 * Holds the engine as a globalThis singleton (survives /reload), registers tools
 * + commands for the 'main' agent and creates background agents via the SDK.
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
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { Engine, type AgentHandle } from "./engine.ts";
import { formatFeedLines, formatKillResult, formatMulticastResult, formatSnapshot, normalizeTargets } from "./feed.ts";
import { formatContext, formatRosterRow } from "./panel-logic.ts";
import { createSubagentsPanel } from "./panel.ts";
import { createSpawner, type ResolvedModel, type SessionLike } from "./spawner.ts";

// Caps — Phase 1: module constants (binding them to settings is a trivial later addition).
const CAPS = { maxAgents: 8, maxSpawnDepth: 3, turnBudget: 100 };

// v2: bumped on the 'user' -> 'main' rename so a stale pre-rename singleton from an
// earlier /reload cannot collide with the new one.
const ENGINE_KEY = "__subagentsEngine_v2";

function getEngine(): Engine {
	const g = globalThis as Record<string, unknown>;
	if (!g[ENGINE_KEY]) g[ENGINE_KEY] = new Engine(CAPS);
	return g[ENGINE_KEY] as Engine;
}

// Delivery to the 'main' agent runs through this globalThis indirection, NOT through a
// captured `pi`. The engine singleton survives /reload and session replacement, but a
// captured `pi` becomes permanently stale (pi loader: state.staleMessage ??= ..., never
// reset). Each freshly loaded instance overwrites the sink with its own live
// pi.sendUserMessage, so the stored main handle never calls a dead pi.
const MAIN_SINK_KEY = "__subagentsMainSink_v2";
type MainSink = (text: string) => void;
function setMainSink(sink: MainSink): void {
	(globalThis as Record<string, unknown>)[MAIN_SINK_KEY] = sink;
}
function deliverToMain(text: string): void {
	const sink = (globalThis as Record<string, unknown>)[MAIN_SINK_KEY] as MainSink | undefined;
	if (!sink) throw new Error("no live foreground session to deliver to 'main'");
	sink(text);
}

function agentSystemPrompt(name: string, systemPrompt: string, spawnedBy: string): string {
	return [
		`You are agent "${name}" in a multi-agent system.`,
		`You were spawned by "${spawnedBy}".`,
		"You can talk to other agents with these tools:",
		"- spawn_agent({name, systemPrompt, model?, message?}): create a new agent (message = optional first task).",
		"- send_message({to, content}): to is an agent name OR a list of names; fire-and-forget (e.g. 'main').",
		"- list_agents(): see who exists.",
		"- kill_agent({name}): terminate an agent or a list of agents (you cannot kill 'main').",
		"Messages you receive are prefixed with [message from <sender>].",
		"To reply, use send_message back to that sender.",
		"",
		systemPrompt,
	].join("\n");
}

// Tool-call preview that shows the FULL parameter content. Without a custom renderCall,
// pi's fallback for registered tools shows only the tool name (see ToolExecutionComponent
// createCallFallback) — long fields like systemPrompt would be missing entirely.
type RenderTheme = { fg(color: string, s: string): string; bold(s: string): string };
function renderToolArgs(toolName: string, args: Record<string, unknown>, theme: RenderTheme): Text {
	const lines = [theme.fg("toolTitle", theme.bold(toolName))];
	for (const [key, value] of Object.entries(args ?? {})) {
		if (typeof value === "string" && value.includes("\n")) {
			lines.push(theme.fg("dim", `  ${key}:`));
			for (const l of value.split("\n")) lines.push(theme.fg("toolOutput", `    ${l}`));
		} else {
			const val = typeof value === "string" ? value : JSON.stringify(value);
			lines.push(`${theme.fg("dim", `  ${key}: `)}${theme.fg("toolOutput", val)}`);
		}
	}
	return new Text(lines.join("\n"), 0, 0);
}

export default function subagents(pi: ExtensionAPI) {
	const engine = getEngine();

	// This (freshly loaded) instance now owns the main delivery with its live pi —
	// replacing a possibly stale sink from a previous instance.
	setMainSink((text) => pi.sendUserMessage(text, { deliverAs: "followUp" }));

	// Process-global services built once (same creds as the foreground).
	const authStorage = AuthStorage.create();
	const modelRegistry = ModelRegistry.create(authStorage);

	// A single stable empty agentDir so background sessions do NOT re-load extensions/skills.
	// It only needs to exist and stay empty; created idempotently so nothing leaks per /reload.
	const blankAgentDir = path.join(os.tmpdir(), "pi-subagents-agentdir");
	fs.mkdirSync(blankAgentDir, { recursive: true });

	// The UI is only available via ctx.ui (ExtensionUIContext), not on `pi`.
	// We cache the reference from session_start so we can update the footer from
	// engine events too (outside a handler ctx).
	type UI = {
		setStatus(key: string, text: string | undefined): void;
		setWidget(key: string, content: string[] | undefined, opts?: { placement?: "aboveEditor" | "belowEditor" }): void;
		theme: { fg(color: string, s: string): string; bg(color: string, s: string): string };
	};
	let ui: UI | undefined;
	// Cache the main context as a VALUE — never hold the ctx itself (it goes stale after a
	// turn/reload; calling a cached ctx crashes pi with "stale ctx").
	type Usage = { tokens: number | null; contextWindow: number; percent: number | null };
	let mainContextUsage: Usage | undefined;
	const captureMainContext = (c: { getContextUsage(): Usage | undefined }) => {
		try {
			mainContextUsage = c.getContextUsage();
		} catch {
			/* ctx stale -> ignore, refreshed on the next handler */
		}
	};
	type ModelLike = { provider: string; id: string };
	let cwd = process.cwd();
	let foregroundModel: ModelLike | undefined; // current foreground model (for inheritance to agents)
	let foregroundStreaming = false;
	// While the /agents panel is open, hide the persistent roster (otherwise doubled).
	let panelOpen = false;

	// Capture the model from every foreground handler ctx (more reliable than model_select alone).
	const captureForegroundModel = (m: ModelLike | undefined) => {
		if (!m) return;
		foregroundModel = { provider: m.provider, id: m.id };
		const u = engine.get("main");
		if (u) u.model = `${m.provider}/${m.id}`;
	};

	const updateStatus = () => {
		if (!ui) return;
		try {
			const agents = engine.list();
			// No footer status — count/running/budget live in the /agents panel header.
			// Permanent roster display above the editor (plan-mode pattern, no overlay).
			// Only show when at least one background agent exists (just 'main' alone is
			// redundant) and the /agents panel is not already open.
			// Only show background agents ('main' = the chat itself, redundant).
			const background = agents.filter((a) => a.name !== "main");
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
				"agents-roster",
				panelOpen || background.length === 0 ? undefined : [...rosterLines, haltLine],
			);
		} catch {
			/* ui from a stale ctx -> skip this tick, refreshes on the next handler */
		}
	};

	// Update the status on every engine event.
	engine.subscribe(() => updateStatus());

	const resolveModel = (ref: string | undefined): ResolvedModel | undefined => {
		if (ref && ref.includes("/")) {
			const slash = ref.indexOf("/");
			const model = modelRegistry.find(ref.slice(0, slash), ref.slice(slash + 1));
			if (model) return { provider: model.provider, id: model.id, model };
		}
		// Fallback: current foreground model (covers inheritance + the "(foreground)" placeholder).
		if (foregroundModel) {
			const model = modelRegistry.find(foregroundModel.provider, foregroundModel.id);
			if (model) return { provider: foregroundModel.provider, id: foregroundModel.id, model };
		}
		return undefined;
	};

	// Tools for a specific agent (name bound fixed) — used for the foreground 'main'
	// via pi.registerTool and for background agents via customTools.
	const makeAgentTools = (selfName: string): ToolDefinition[] => [
		{
			name: "spawn_agent",
			label: "Spawn Agent",
			renderCall: (args, theme) => renderToolArgs("spawn_agent", args as Record<string, unknown>, theme as RenderTheme),
			description:
				"Create a new agent with a system prompt; optionally deliver a first message. It can then be messaged by name.",
			parameters: Type.Object({
				name: Type.String({ description: "Unique agent name ([a-zA-Z0-9_-])" }),
				systemPrompt: Type.String({ description: "System prompt defining the agent's behavior" }),
				model: Type.Optional(Type.String({ description: "provider/id; default: inherited" })),
				message: Type.Optional(
					Type.String({ description: "Optional first message delivered to the new agent right after spawn" }),
				),
			}),
			execute: async (_id, args) => {
				const res = await spawnAgent(args, selfName);
				return { content: [{ type: "text", text: res.msg }], details: {} };
			},
		},
		{
			name: "send_message",
			label: "Send Message",
			renderCall: (args, theme) => renderToolArgs("send_message", args as Record<string, unknown>, theme as RenderTheme),
			description: "Fire-and-forget message to one agent or a list of agents (e.g. 'main'). Returns immediately.",
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
			renderCall: (args, theme) => renderToolArgs("list_agents", args as Record<string, unknown>, theme as RenderTheme),
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
			renderCall: (args, theme) => renderToolArgs("kill_agent", args as Record<string, unknown>, theme as RenderTheme),
			description: "Terminate one agent or a list of agents. 'main' cannot be killed.",
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

	// SDK adapter: creates an isolated background agent session.
	const createSession = async (spec: {
		name: string;
		systemPrompt: string;
		spawnedBy: string;
		model: unknown;
	}): Promise<SessionLike> => {
		const loader = new DefaultResourceLoader({
			cwd,
			agentDir: blankAgentDir,
			systemPromptOverride: () => agentSystemPrompt(spec.name, spec.systemPrompt, spec.spawnedBy),
		});
		await loader.reload();

		// Leave the built-in tool allowlist unset so the agent inherits the full default
		// foreground toolset, plus the four custom agent tools via customTools.
		const { session } = await createAgentSession({
			cwd,
			model: spec.model as Parameters<typeof createAgentSession>[0]["model"],
			authStorage,
			modelRegistry,
			customTools: makeAgentTools(spec.name),
			resourceLoader: loader,
			sessionManager: SessionManager.inMemory(cwd),
		});
		return session;
	};

	const { spawnAgent } = createSpawner({ engine, resolveModel, createSession, onActivity: updateStatus });

	// Capture the foreground model (for inheritance to spawned agents).
	pi.on("model_select", (event) => {
		captureForegroundModel(event.model);
	});

	// Capture the foreground streaming flag for the status display + the model.
	pi.on("agent_start", (_event, ctx) => {
		ui = ctx.ui;
		captureForegroundModel(ctx.model);
		captureMainContext(ctx);
		foregroundStreaming = true;
		engine.setStreaming("main", true);
		updateStatus();
	});
	pi.on("agent_end", (_event, ctx) => {
		ui = ctx.ui;
		captureMainContext(ctx);
		foregroundStreaming = false;
		engine.setStreaming("main", false);
		updateStatus();
	});

	// Register the 'main' agent (foreground). Delivery to main via pi.sendUserMessage.
	pi.on("session_start", (_event, ctx) => {
		cwd = ctx.cwd;
		ui = ctx.ui;
		ctx.ui.setStatus("agents", undefined); // footer status no longer used (info lives in the panel)
		captureMainContext(ctx);
		captureForegroundModel(ctx.model);
		if (!engine.has("main")) {
			const mainHandle: AgentHandle = {
				// via the globalThis indirection so the singleton handle never uses a stale pi.
				deliver: async (text) => {
					deliverToMain(text);
				},
				abort: async () => {}, // do not abort the human's turn
				isStreaming: () => foregroundStreaming,
			};
			engine.addAgent({
				name: "main",
				model: foregroundModel ? `${foregroundModel.provider}/${foregroundModel.id}` : "(foreground)",
				handle: mainHandle,
				spawnedBy: "main",
				depth: 0,
				createdAt: Date.now(),
				turns: 0,
				lastActivity: Date.now(),
				streaming: false,
				view: {
					getMessages: () => [], // main transcript = the main chat (not mirrored)
					getContextUsage: () => mainContextUsage, // cached VALUE, not a stale ctx
					subscribe: () => () => {},
				},
			});
		}
		updateStatus();
	});

	// Register the foreground tools for 'main'.
	for (const tool of makeAgentTools("main")) {
		pi.registerTool(tool);
	}

	pi.registerCommand("halt", {
		description: "Freeze all agents (stop new turns, abort running background agents).",
		handler: async (_args, ctx) => {
			engine.halt();
			for (const a of engine.list()) {
				if (a.name !== "main") void a.handle.abort();
			}
			ctx.ui.notify("Agents halted. Use /unhalt to continue.", "warning");
			updateStatus();
		},
	});

	// Note: not "resume" — that collides with pi's built-in /resume (continue session).
	pi.registerCommand("unhalt", {
		description: "Resume halted agents and reset the turn budget.",
		handler: async (_args, ctx) => {
			engine.resume();
			ctx.ui.notify("Agents resumed; turn budget reset.", "info");
			updateStatus();
		},
	});

	pi.registerCommand("killall", {
		description: "Terminate all agents (except 'main').",
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

	// /agents opens the panel as a fullscreen takeover (no overlay — that froze).
	pi.registerCommand("agents", {
		description: "Open the agents panel (Esc to close)",
		handler: async (_args, ctx) => {
			ui = ctx.ui;
			panelOpen = true;
			updateStatus(); // hide the redundant persistent roster
			try {
				await ctx.ui.custom<void>((tui, theme, _kb, done) =>
					createSubagentsPanel({ engine, cwd, route: (to, content) => void engine.route("main", to, content) }, tui, theme, done),
				);
			} finally {
				panelOpen = false;
				updateStatus(); // show the persistent roster again
			}
		},
	});
}
