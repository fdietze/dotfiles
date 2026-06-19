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
	SettingsManager,
	type ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { Text, truncateToWidth } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { Engine, statusLabel, type AgentHandle } from "./engine.ts";
import { formatFeedLines, formatKillResult, formatMulticastResult, formatSnapshot, normalizeTargets } from "./feed.ts";
import { formatContext, formatHistory, formatRosterRow, formatSendTargets, swarmStateLine } from "./panel-logic.ts";
import { createSubagentsPanel } from "./panel.ts";
import { danglingToolResultIds, deriveStatus, type RawMessage } from "./persistence-logic.ts";
import { readRoster, subagentsDir, writeRoster } from "./persistence.ts";
import { createSpawner, type ResolvedModel, type SessionLike } from "./spawner.ts";

// Caps — Phase 1: module constants (binding them to settings is a trivial later addition).
const CAPS = { maxAgents: 8, maxSpawnDepth: 3, turnBudget: 200 };

// Fired to each halted agent on resume to re-trigger its interrupted work. Fixed text
// (not main-authored) so resume stays a single tool call from main's side.
const RESUME_NUDGE = "[resumed] continue your interrupted work";
// Injected into 'main' when the swarm halts on the turn budget (not on manual /halt).
const BUDGET_ESCALATION = (total: number) =>
	`turn budget (${total}) exhausted, swarm halted. resume_agents() to re-arm and continue. ` +
	`If turns ran higher than expected, inspect with list_agents before resuming.`;

// The Engine is a globalThis singleton so it survives /reload. Consequence: a persisted
// instance keeps the SHAPE (methods) of the code that built it — adding/changing Engine
// methods requires bumping this key, else the old instance lacks them ("x is not a
// function") and throws inside event callbacks.
// v2: 'user' -> 'main' rename. v3: added setActivity (fine-grained status phases).
// v4: halt(reason)+frozenReason, freeze-by-blocking recordTurnStart, halted flag, 200 cap.
// v5: AgentRecord gains systemPrompt+sessionFile (persistence roster), attach() sets them.
// v6: Engine gains setCustomStatus + AgentRecord.customStatus (agent-settable status line).
const ENGINE_KEY = "__subagentsEngine_v6";

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

// Live foreground state read by the singleton 'main' record. Same reason as MAIN_SINK_KEY:
// the engine (and thus main's view/handle closures) survive /reload, but each reloaded
// instance has fresh locals. Storing the state on globalThis lets the new instance update
// the SAME object the stored closures read, so main's ctx%/streaming never go stale.
const MAIN_STATE_KEY = "__subagentsMainState_v1";
type MainLiveState = { usage: { tokens: number | null; contextWindow: number; percent: number | null } | undefined; streaming: boolean };
function mainState(): MainLiveState {
	const g = globalThis as Record<string, unknown>;
	let s = g[MAIN_STATE_KEY] as MainLiveState | undefined;
	if (!s) {
		s = { usage: undefined, streaming: false };
		g[MAIN_STATE_KEY] = s;
	}
	return s;
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
		"- set_status({status}): set your short status line (shown to others in list_agents); empty string clears.",
		"Messages you receive are prefixed with [message from <sender>].",
		"",
		"CRITICAL — how communication works: other agents and main CANNOT see your thinking or",
		"your normal response text. The ONLY channel between agents is the send_message tool. A",
		"turn that ends WITHOUT a send_message call communicates nothing to anyone and silently",
		"stalls the conversation. Whenever you owe a reply, a progress update, or a final result,",
		"you MUST end that turn with a send_message call. To reply to a sender, send_message back",
		"to that sender. You can inspect any agent's transcript with agent_history.",
		"",
		"Reporting rule:",
		`- Report to your parent ("${spawnedBy}") ONLY final results or blockers you cannot resolve yourself.`,
		"- Keep intermediate states, status updates and work steps lateral (peers) or downward (your own subagents) — never escalate them upward.",
		"- One message to your parent = one finished deliverable or a decision only the parent can make.",
		"",
		"Event-driven — do NOT poll or busy-wait: you run only when a message arrives. After you",
		"act, END YOUR TURN and go idle; you are automatically re-woken the moment another agent",
		"messages you. Never poll list_agents in a loop or try to 'wait' for a subagent to finish",
		"— it wastes turns. If you spawned several agents, you are woken once per reply: track what",
		"is still outstanding and finish only when all expected replies are in. Inspect",
		"(list_agents/agent_history) only when you suspect a problem, not as a waiting mechanism.",
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
	// deliverAs "steer": deliver agent->main messages at main's next turn boundary instead
	// of only when main fully stops. Critical for the common "poll list_agents until done"
	// loop: with "followUp" the replies queue while main streams and main never observes
	// them mid-loop (polls forever). "steer" injects them before main's next LLM call so it
	// sees the replies. Idle main starts a turn immediately either way (non-destructive).
	setMainSink((text) => pi.sendUserMessage(text, { deliverAs: "steer" }));

	// Process-global services built once (same creds as the foreground).
	const authStorage = AuthStorage.create();
	const modelRegistry = ModelRegistry.create(authStorage);

	// Background agents share main's real agentDir so they inherit the SAME global AGENTS.md
	// and global skills. Extensions are suppressed separately (noExtensions in createSession),
	// which is the only thing we must keep out: loading them headless would re-run THIS
	// extension (re-registering spawn_agent etc. + building another engine) and the
	// interactive question.ts extension, neither of which works in a background SDK session.
	const realAgentDir = path.join(os.homedir(), ".pi/agent");

	// Where this main session's background agent files + roster live. Set at session_start
	// from the main session; undefined until then (and for an in-memory main session) -> new
	// agents fall back to in-memory (no persistence).
	let subDir: string | undefined;

	// Read the live hideThinkingBlock setting (the static config AND the ctrl+t runtime toggle
	// both persist to it). reload() picks up runtime toggles; we read fresh per panel-open and
	// per agent_history call so subagent thinking display stays aligned with the main UI.
	let settingsMgr: SettingsManager | undefined;
	const getHideThinking = async (): Promise<boolean> => {
		try {
			if (!settingsMgr) settingsMgr = SettingsManager.create(cwd, realAgentDir);
			await settingsMgr.reload();
			return settingsMgr.getHideThinkingBlock();
		} catch {
			return false;
		}
	};

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
	const captureMainContext = (c: { getContextUsage(): MainLiveState["usage"] }) => {
		try {
			mainState().usage = c.getContextUsage();
		} catch {
			/* ctx stale -> ignore, refreshed on the next handler */
		}
	};
	type ModelLike = { provider: string; id: string };
	let cwd = process.cwd();
	let foregroundModel: ModelLike | undefined; // current foreground model (for inheritance to agents)
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
			const styler = (label: string, busy: boolean) =>
				busy ? theme.bg("toolSuccessBg", label) : theme.fg("dim", label);
			const matrix = engine.getMessageMatrix();
			// EVERY widget line must fit the live terminal width or pi's renderer throws
			// ("Rendered line N exceeds terminal width"). pi checks against this.terminal.columns,
			// so truncate each composed line to process.stdout.columns (NOT a hardcoded width —
			// that crashed on narrower terminals). truncateToWidth is ANSI/unicode aware.
			const width = process.stdout.columns ?? 80;
			const rosterLines = background.map((a) =>
				truncateToWidth(
					formatRosterRow(
						{
							name: a.name,
							model: a.model,
							context: formatContext(a.view?.getContextUsage()),
							status: statusLabel(a),
							customStatus: a.customStatus,
							targets: formatSendTargets(matrix, a.name),
						},
						false,
						width,
						styler,
					),
					width,
				),
			);
			const running = background.filter((a) => a.streaming).length;
			const stateLine = swarmStateLine(engine.isFrozen(), running);
			const haltLine = engine.isFrozen()
				? theme.bg("toolPendingBg", truncateToWidth(stateLine.padEnd(width), width))
				: theme.bg("selectedBg", truncateToWidth(stateLine, width));
			// Same header the /agents panel shows, so the turn budget is always visible at a
			// glance (matters for the budget-halt escalation) — not only inside the panel.
			const { used, total } = engine.budget;
			const header = theme.fg(
				"accent",
				truncateToWidth(`─ agents · ${background.length} agents · ${running} running · budget ${used}/${total} `, width),
			);
			ui.setWidget(
				"agents-roster",
				panelOpen || background.length === 0 ? undefined : [header, ...rosterLines, haltLine],
			);
		} catch {
			/* ui from a stale ctx -> skip this tick, refreshes on the next handler */
		}
	};

	// Update the status on every engine event; escalate budget-halts to 'main' exactly once
	// (the halt event fires once — the frozen guard in recordTurnStart prevents re-entry).
	// Manual /halt does NOT escalate (the human initiated it).
	engine.subscribe((e) => {
		if (e.type === "halt" && e.reason === "budget") {
			try {
				deliverToMain(BUDGET_ESCALATION(engine.budget.total));
			} catch {
				/* no live foreground session — escalation surfaces in /feed + panel instead */
			}
		}
		updateStatus();
	});

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
				"Create a new agent with a system prompt; optionally deliver a first message. It can then be messaged by name. " +
				"Event-driven & fire-and-forget: after spawning, END YOUR TURN — you are automatically re-woken when an agent " +
				"messages you back. Do NOT poll list_agents or wait in a loop for completion; it wastes turns. Inspect " +
				"(list_agents/agent_history) only if you suspect something went wrong.",
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
				persistRoster();
				return { content: [{ type: "text", text: res.msg }], details: {} };
			},
		},
		{
			name: "send_message",
			label: "Send Message",
			renderCall: (args, theme) => renderToolArgs("send_message", args as Record<string, unknown>, theme as RenderTheme),
			description:
				"Fire-and-forget message to one agent or a list of agents (e.g. 'main'). Returns immediately. After sending, " +
				"END YOUR TURN — you are automatically re-woken if a reply arrives. Do NOT poll or wait in a loop; inspect only " +
				"if you suspect a problem.",
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
				return { content: [{ type: "text", text: formatSnapshot(engine.list(), used, total, selfName) }], details: {} };
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
				persistRoster();
				return { content: [{ type: "text", text: formatKillResult(results) }], details: {} };
			},
		},
		{
			name: "agent_history",
			label: "Agent History",
			renderCall: (args, theme) => renderToolArgs("agent_history", args as Record<string, unknown>, theme as RenderTheme),
			description:
				"Inspect any agent's message transcript. offset: start index (0 = beginning, the default; " +
				"negative = from the end, e.g. -30 = last 30). limit: window size (default 30). The header " +
				"reports the total message count and the shown range so you can page through.",
			parameters: Type.Object({
				name: Type.String({ description: "agent whose history to inspect" }),
				offset: Type.Optional(Type.Number({ description: "start index; 0=beginning (default), negative=from end" })),
				limit: Type.Optional(Type.Number({ description: "number of messages to show (default 30)" })),
			}),
			execute: async (_id, args) => {
				const rec = engine.get(args.name);
				if (!rec) return { content: [{ type: "text", text: `unknown agent '${args.name}'` }], details: {} };
				const text = formatHistory({
					name: args.name,
					systemPrompt: rec.view?.getSystemPrompt?.(),
					messages: (rec.view?.getMessages() ?? []) as { role?: string; content?: unknown }[],
					offset: args.offset,
					limit: args.limit,
					hideThinking: await getHideThinking(),
				});
				return { content: [{ type: "text", text }], details: {} };
			},
		},
		{
			name: "set_status",
			label: "Set Status",
			renderCall: (args, theme) => renderToolArgs("set_status", args as Record<string, unknown>, theme as RenderTheme),
			description:
				"Set your short status line shown in list_agents and the agents panel " +
				"(e.g. 'parsing 500 files', 'waiting on review'). Pass empty string to clear. " +
				"Keep it to ~20 characters — one terse phrase (longer is truncated in the roster). " +
				"It must describe your CURRENT state, not a past action. Update it when your phase " +
				"changes, and before you END A TURN and go idle set it to a resting/outcome state " +
				"(e.g. 'done', 'waiting for critic', 'blocked: needs X') or clear it — never leave a " +
				"stale in-progress phrase like 'sending to editor' once you are idle.",
			parameters: Type.Object({
				status: Type.String({ description: "Short status phrase; empty clears" }),
			}),
			execute: async (_id, args) => {
				engine.setCustomStatus(selfName, args.status);
				updateStatus();
				return {
					content: [{ type: "text", text: args.status ? `status set: ${args.status}` : "status cleared" }],
					details: {},
				};
			},
		},
	];

	// Repair a crash-truncated transcript before the LLM sees it: a kill between persisting an
	// assistant tool_use and its tool_result leaves a dangling tool_use, which providers reject.
	// pi does NOT reconcile on load (verified: convertToLlm + buildSessionContext pass messages
	// verbatim), so synthesize the missing tool_result here. appendMessage also rewrites the file.
	const reconcileDangling = (sm: SessionManager): void => {
		const msgs = sm.buildSessionContext().messages as RawMessage[];
		for (const { id, name } of danglingToolResultIds(msgs)) {
			sm.appendMessage({
				role: "toolResult",
				toolCallId: id,
				toolName: name,
				content: [{ type: "text", text: "Interrupted — not completed" }],
				isError: true,
				timestamp: Date.now(),
			} as never);
		}
	};

	// SDK adapter: creates an isolated background agent session. With existingFile it reopens a
	// persisted session (restart resume); otherwise it starts a fresh persisted session under
	// subDir (or in-memory when no main-session dir is available).
	const createSession = async (
		spec: { name: string; systemPrompt: string; spawnedBy: string; model: unknown },
		existingFile?: string,
	): Promise<{ session: SessionLike; sessionFile?: string }> => {
		const loader = new DefaultResourceLoader({
			cwd,
			agentDir: realAgentDir,
			// Inherit global + project AGENTS.md and skills, but NOT extensions (see realAgentDir).
			noExtensions: true,
			systemPromptOverride: () => agentSystemPrompt(spec.name, spec.systemPrompt, spec.spawnedBy),
		});
		await loader.reload();

		let sm: SessionManager;
		if (existingFile) {
			sm = SessionManager.open(existingFile);
			reconcileDangling(sm);
		} else if (subDir) {
			fs.mkdirSync(subDir, { recursive: true });
			sm = SessionManager.create(cwd, subDir);
			try {
				(sm as { setSessionName?: (n: string) => void }).setSessionName?.(spec.name);
			} catch {
				/* display name is cosmetic; ignore if unsupported */
			}
		} else {
			sm = SessionManager.inMemory(cwd);
		}

		// Leave the built-in tool allowlist unset so the agent inherits the full default
		// foreground toolset, plus the four custom agent tools via customTools.
		const { session } = await createAgentSession({
			cwd,
			model: spec.model as Parameters<typeof createAgentSession>[0]["model"],
			authStorage,
			modelRegistry,
			customTools: makeAgentTools(spec.name),
			resourceLoader: loader,
			sessionManager: sm,
		});
		// Inter-agent messages are delivered with deliverAs "steer"; "all" steering mode makes
		// every queued message arrive at the next turn boundary (default "one-at-a-time" would
		// drip-feed one per completed turn).
		session.setSteeringMode("all");
		return { session, sessionFile: sm.getSessionFile() };
	};

	const { spawnAgent, restoreAgent } = createSpawner({ engine, resolveModel, createSession, onActivity: updateStatus });

	// Overwrite roster.json with current background membership (called after spawn/kill).
	// Best-effort: persistence must never break the swarm.
	const persistRoster = (): void => {
		if (!subDir) return;
		try {
			writeRoster(subDir, engine.list());
		} catch {
			/* best-effort */
		}
	};

	// Restore-once guard keyed by subDir; on globalThis so it survives /reload (which must NOT
	// re-restore — the singleton still holds the live agents).
	const restoredSet = (): Set<string> => {
		const g = globalThis as Record<string, unknown>;
		let s = g.__subagentsRestored_v1 as Set<string> | undefined;
		if (!s) {
			s = new Set();
			g.__subagentsRestored_v1 = s;
		}
		return s;
	};

	// Cold-start rebuild of a persisted swarm AS HALTED: reopen each agent file, reconcile any
	// crash damage, derive idle-vs-halted from the transcript tail, register frozen. The
	// existing resume_agents()/`/unhalt` then re-triggers exactly the halted agents.
	const restoreSwarm = async (): Promise<void> => {
		if (!subDir) return;
		// Skip if the swarm is already populated (/reload) or already restored this session.
		if (engine.list().some((a) => a.name !== "main")) return;
		const done = restoredSet();
		if (done.has(subDir)) return;
		done.add(subDir);
		const roster = readRoster(subDir);
		if (!roster.length) return;
		let restored = 0;
		for (const entry of roster) {
			if (!fs.existsSync(entry.sessionFile)) continue; // file gone -> skip
			const resolved = resolveModel(entry.model);
			if (!resolved) continue; // model no longer available -> skip
			try {
				const { session, sessionFile } = await createSession(
					{ name: entry.name, systemPrompt: entry.systemPrompt, spawnedBy: entry.spawnedBy, model: resolved.model },
					entry.sessionFile,
				);
				restoreAgent({
					name: entry.name,
					spawnedBy: entry.spawnedBy,
					depth: entry.depth,
					model: `${resolved.provider}/${resolved.id}`,
					systemPrompt: entry.systemPrompt,
					sessionFile: sessionFile ?? entry.sessionFile,
					session,
					halted: deriveStatus(session.messages as RawMessage[]) === "halted",
				});
				restored++;
			} catch {
				/* skip an unrestorable agent */
			}
		}
		// Present the restored swarm as halted: one resume_agents()/`/unhalt` reactivates it.
		if (restored > 0) engine.halt("manual");
	};

	// Shared by /unhalt and the resume_agents tool: re-arm the budget, unfreeze, and
	// re-trigger only the halted agents (idle agents finished naturally — nothing to do).
	// resume() must precede the nudge: route() rejects delivery while frozen.
	const resumeAgents = (): number => {
		const halted = engine
			.list()
			.filter((a) => a.name !== "main" && a.halted)
			.map((a) => a.name);
		engine.resume();
		for (const name of halted) void engine.route("main", name, RESUME_NUDGE);
		updateStatus();
		return halted.length;
	};

	// Capture the foreground model (for inheritance to spawned agents).
	pi.on("model_select", (event) => {
		captureForegroundModel(event.model);
	});

	// Capture the foreground streaming flag for the status display + the model.
	pi.on("agent_start", (_event, ctx) => {
		ui = ctx.ui;
		captureForegroundModel(ctx.model);
		captureMainContext(ctx);
		mainState().streaming = true;
		engine.setStreaming("main", true);
		engine.setActivity("main", "thinking");
		updateStatus();
	});
	// Mirror the background phase tracking for 'main' so its status reads consistently.
	pi.on("message_update", (event) => {
		const sub = (event as { assistantMessageEvent?: { type?: string } }).assistantMessageEvent?.type;
		if (sub === "thinking_start") engine.setActivity("main", "thinking");
		else if (sub === "text_start" || sub === "toolcall_start") engine.setActivity("main", "writing");
		else return;
		updateStatus();
	});
	pi.on("tool_execution_start", (event) => {
		engine.setActivity("main", "tool", (event as { toolName?: string }).toolName);
		updateStatus();
	});
	pi.on("agent_end", (_event, ctx) => {
		ui = ctx.ui;
		captureMainContext(ctx);
		mainState().streaming = false;
		engine.setStreaming("main", false);
		updateStatus();
	});

	// Register the 'main' agent (foreground). Delivery to main via pi.sendUserMessage.
	pi.on("session_start", async (_event, ctx) => {
		cwd = ctx.cwd;
		ui = ctx.ui;
		ctx.ui.setStatus("agents", undefined); // footer status no longer used (info lives in the panel)
		captureMainContext(ctx);
		captureForegroundModel(ctx.model);
		// Locate this main session's subagents dir (persistence + restore are keyed by it).
		try {
			const id = ctx.sessionManager.getSessionId();
			const dir = ctx.sessionManager.getSessionDir();
			subDir = id && dir ? subagentsDir(dir, id) : undefined;
		} catch {
			subDir = undefined;
		}
		if (!engine.has("main")) {
			const mainHandle: AgentHandle = {
				// via the globalThis indirection so the singleton handle never uses a stale pi.
				deliver: async (text) => {
					deliverToMain(text);
				},
				abort: async () => {}, // do not abort the human's turn
				isStreaming: () => mainState().streaming,
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
					getContextUsage: () => mainState().usage, // globalThis-backed, survives /reload
					subscribe: () => () => {},
				},
			});
		}
		await restoreSwarm();
		updateStatus();
	});

	// Register the foreground tools for 'main'. set_status is background-only: main has
	// ctx.ui.setStatus() + the human watches the chat directly, so a second status channel
	// would only confuse.
	for (const tool of makeAgentTools("main")) {
		if (tool.name === "set_status") continue;
		pi.registerTool(tool);
	}

	// Main-only: deciding whether the halted group continues is main's call. NOT added to
	// makeAgentTools (background agents must not self-resume the swarm).
	pi.registerTool({
		name: "resume_agents",
		label: "Resume Agents",
		description:
			"Re-arm the turn budget and resume halted agents (re-trigger their interrupted work). " +
			"Call after the swarm halts on the turn budget to let the group continue.",
		parameters: Type.Object({}),
		execute: async () => {
			const n = resumeAgents();
			return {
				content: [{ type: "text", text: n ? `resumed ${n} halted agent(s); budget re-armed` : "no halted agents; budget re-armed" }],
				details: {},
			};
		},
	});

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
		description: "Resume halted agents (re-trigger their work) and reset the turn budget.",
		handler: async (_args, ctx) => {
			const n = resumeAgents();
			ctx.ui.notify(
				n ? `Resumed ${n} halted agent(s); turn budget reset.` : "Agents resumed; turn budget reset.",
				"info",
			);
		},
	});

	pi.registerCommand("killall", {
		description: "Terminate all agents (except 'main').",
		handler: async (_args, ctx) => {
			const killed = engine.killAll();
			persistRoster();
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
			const hideThinking = await getHideThinking(); // align panel thinking with the main UI
			try {
				await ctx.ui.custom<void>((tui, theme, _kb, done) =>
					createSubagentsPanel(
						{ engine, cwd, hideThinking, route: (to, content) => void engine.route("main", to, content) },
						tui,
						theme,
						done,
					),
				);
			} finally {
				panelOpen = false;
				updateStatus(); // show the persistent roster again
			}
		},
	});
}
