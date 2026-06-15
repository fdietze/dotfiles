/**
 * Context Prune - der Agent bearbeitet seinen eigenen Kontext.
 *
 * Idee: Jede Conversation-Message bekommt im `context`-Event (nur fuer den
 * jeweiligen LLM-Call, non-destruktiv) einen sichtbaren `[#id]`-Marker
 * vorangestellt. Der Agent referenziert damit Messages und ruft
 * `forget_messages({ ids })` bzw. `recall_messages({ ids })`.
 *
 * Warum Marker im Text statt im JSON: Der Provider serialisiert nur `role` +
 * `content`; Zusatzfelder am Message-Objekt erreichen das Modell nie. Die
 * Entry-`id` lebt zudem nur am Session-*Entry* (getBranch()), nicht an der
 * AgentMessage (siehe docs/session-format.md). Deshalb wird im context-Handler
 * Entry<->Message ueber `timestamp`+`role` korreliert (gemeinsamer, 1:1
 * kopierter Schluessel), dann der Marker in den ersten Text-Block gepatcht.
 *
 * Warum "vergessen" = Tombstone statt echtes Entfernen: toolCall/toolResult
 * sind gepaart; ein hartes Entfernen wuerde Paare verwaisen lassen (Provider-
 * Fehler) oder die Rollen-Alternation brechen. Der Tombstone ersetzt nur den
 * (grossen) Content, behaelt die Struktur und ist voll reversibel.
 *
 * Persistenz: Der kumulative Pruned-Set wird via pi.appendEntry als Custom-
 * Entry in die Session geschrieben und in session_start/session_tree wieder
 * rekonstruiert (analog examples/extensions/todo.ts) -> ueberlebt /reload und
 * folgt korrekt der Branch-History.
 *
 * Doku: docs/extensions.md ("context" event, registerTool, appendEntry),
 *       docs/session-format.md (Entry/Message-Typen, getBranch, ids).
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// Custom-Entry-Typ fuer die persistierte Pruned-Liste.
const PRUNE_ENTRY = "context-prune";

// Rollen, die einen sichtbaren Marker bekommen und vergessen werden koennen.
const TAGGABLE_ROLES = new Set(["user", "assistant", "toolResult"]);

type Content = string | Array<{ type?: string; text?: string }>;
interface AgentMessageLike {
	role: string;
	content: Content;
	timestamp?: number;
	details?: unknown;
	toolCallId?: string;
	toolName?: string;
	isError?: boolean;
}

interface PruneDetails {
	action: "forget" | "recall";
	applied: string[];
	unknown: string[];
	noop: string[];
	total: number;
}

// Eine zusammengefasste Range: ihre Summary-Message erbt fromId (= erstes
// Member) als sichtbare id, damit sie selbst wieder in eine Range aufgenommen
// und per recall aufgeloest werden kann. memberIds sind immer echte Entry-ids
// (flach), zusammenhaengend und in Branch-Reihenfolge aufsteigend.
interface Span {
	fromId: string;
	memberIds: string[];
	summary: string;
}

// Marker, den der Agent liest und an forget/recall zurueckgibt.
const marker = (id: string) => `[#${id}]`;

/** Sichtbaren `[#id]`-Marker an den ersten Text-Block voranstellen. */
function tag(message: AgentMessageLike, id: string): void {
	const prefix = `${marker(id)} `;
	if (typeof message.content === "string") {
		message.content = prefix + message.content;
		return;
	}
	const blocks = message.content;
	const textIdx = blocks.findIndex((b) => b?.type === "text");
	if (textIdx >= 0) {
		blocks[textIdx] = { ...blocks[textIdx], text: prefix + (blocks[textIdx].text ?? "") };
		return;
	}
	// Kein Text-Block (z.B. Assistant nur mit toolCall): nach fuehrenden
	// thinking-Bloecken einfuegen, damit die Provider-Reihenfolge stimmt.
	let insertAt = 0;
	while (insertAt < blocks.length && blocks[insertAt]?.type === "thinking") insertAt++;
	blocks.splice(insertAt, 0, { type: "text", text: marker(id) });
}

/**
 * Content durch einen Tombstone ersetzen. Erhaelt Pairing/Struktur:
 * - toolResult: Output blanken, toolCallId/Rolle bleiben -> Paar intakt.
 * - assistant: toolCall-Bloecke behalten (klein, fuer Pairing noetig),
 *   Text/Thinking durch Marker ersetzen.
 * - user/sonst: kompletter Content -> Marker.
 */
function tombstone(message: AgentMessageLike, id: string): void {
	const note = `${marker(id)} (forgotten)`;
	if (message.role === "toolResult") {
		message.content = [{ type: "text", text: note }];
		message.details = undefined;
		return;
	}
	if (message.role === "assistant" && Array.isArray(message.content)) {
		const toolCalls = message.content.filter((b) => b?.type === "toolCall");
		message.content = [{ type: "text", text: note }, ...toolCalls];
		return;
	}
	message.content = note;
}

export default function (pi: ExtensionAPI) {
	// In-memory Quelle der Wahrheit, aus der Session rekonstruiert.
	const pruned = new Set<string>();
	const spans: Span[] = [];

	const reconstruct = (ctx: ExtensionContext) => {
		pruned.clear();
		spans.length = 0;
		// Letzter Custom-Entry auf dem Branch gewinnt (kumulativer Snapshot).
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === PRUNE_ENTRY) {
				const data = entry.data as { pruned?: string[]; spans?: Span[] } | undefined;
				pruned.clear();
				spans.length = 0;
				for (const id of data?.pruned ?? []) pruned.add(id);
				for (const s of data?.spans ?? []) spans.push(s);
			}
		}
	};
	const persist = () => pi.appendEntry(PRUNE_ENTRY, { pruned: [...pruned], spans });

	pi.on("session_start", async (_event, ctx) => reconstruct(ctx));
	pi.on("session_tree", async (_event, ctx) => reconstruct(ctx));

	// Marker injizieren bzw. vergessene Messages tombstonen - jedes Mal
	// deterministisch, damit das Prompt-Caching stabil bleibt.
	pi.on("context", async (event, ctx) => {
		// Entry-ids in Branch-Reihenfolge pro (timestamp,role) als Queue, um
		// gleiche Schluessel positionsstabil zu konsumieren.
		const idQueues = new Map<string, string[]>();
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type !== "message") continue;
			const msg = entry.message as AgentMessageLike;
			if (!TAGGABLE_ROLES.has(msg.role)) continue;
			const key = `${msg.timestamp}|${msg.role}`;
			const queue = idQueues.get(key) ?? idQueues.set(key, []).get(key)!;
			queue.push(entry.id);
		}

		for (const message of event.messages as AgentMessageLike[]) {
			if (!TAGGABLE_ROLES.has(message.role)) continue;
			const id = idQueues.get(`${message.timestamp}|${message.role}`)?.shift();
			if (!id) continue;
			if (pruned.has(id)) tombstone(message, id);
			else tag(message, id);
		}
		return { messages: event.messages };
	});

	// Gueltige (vergessbare) Message-Entry-ids auf dem aktuellen Branch.
	const validIds = (ctx: ExtensionContext): Set<string> => {
		const ids = new Set<string>();
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "message" && TAGGABLE_ROLES.has((entry.message as AgentMessageLike).role)) {
				ids.add(entry.id);
			}
		}
		return ids;
	};

	const summarize = (action: "forget" | "recall", applied: string[], unknown: string[], noop: string[]): string => {
		const parts: string[] = [];
		const verb = action === "forget" ? "Forgot" : "Recalled";
		parts.push(applied.length ? `${verb} ${applied.length} message(s): ${applied.join(", ")}` : `${verb} nothing`);
		if (noop.length) parts.push(`already ${action === "forget" ? "forgotten" : "active"}: ${noop.join(", ")}`);
		if (unknown.length) parts.push(`unknown id(s): ${unknown.join(", ")}`);
		return parts.join(". ");
	};

	const IdsParam = Type.Object({
		ids: Type.Array(Type.String(), {
			description: "Message ids from their [#id] markers (the 8-char hex inside the brackets).",
		}),
	});

	pi.registerTool({
		name: "forget_messages",
		label: "Forget Messages",
		description:
			"Drop the content of earlier messages from the model context by their [#id] markers. " +
			"Tool outputs and superseded exchanges are good candidates. Reversible via recall_messages.",
		promptSnippet: "Free context by forgetting earlier messages via their [#id] markers",
		promptGuidelines: [
			"Every message is prefixed with a [#id] marker; pass those ids to forget_messages to remove their content from context, or recall_messages to restore them.",
			"The [#id] markers are added automatically by the harness. Never write, echo, or fabricate them in your own output; only pass ids that already appear as markers to the forget_messages/recall_messages tools.",
			"Prefer forget_messages on large, no-longer-needed tool outputs to reclaim context budget.",
		],
		parameters: IdsParam,
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const valid = validIds(ctx);
			const applied: string[] = [];
			const unknown: string[] = [];
			const noop: string[] = [];
			for (const id of params.ids) {
				if (!valid.has(id)) unknown.push(id);
				else if (pruned.has(id)) noop.push(id);
				else {
					pruned.add(id);
					applied.push(id);
				}
			}
			if (applied.length) persist();
			return {
				content: [{ type: "text", text: summarize("forget", applied, unknown, noop) }],
				details: { action: "forget", applied, unknown, noop, total: pruned.size } as PruneDetails,
			};
		},
		renderResult(result, _opts, theme) {
			const d = result.details as PruneDetails | undefined;
			if (!d) return new Text("", 0, 0);
			return new Text(theme.fg("success", `✓ forgot ${d.applied.length}`) + theme.fg("dim", ` (${d.total} total)`), 0, 0);
		},
	});

	pi.registerTool({
		name: "recall_messages",
		label: "Recall Messages",
		description: "Restore previously forgotten messages back into context by their [#id] markers.",
		parameters: IdsParam,
		async execute(_id, params, _signal, _onUpdate, _ctx) {
			const applied: string[] = [];
			const noop: string[] = [];
			for (const id of params.ids) {
				if (pruned.delete(id)) applied.push(id);
				else noop.push(id);
			}
			if (applied.length) persist();
			return {
				content: [{ type: "text", text: summarize("recall", applied, [], noop) }],
				details: { action: "recall", applied, unknown: [], noop, total: pruned.size } as PruneDetails,
			};
		},
		renderResult(result, _opts, theme) {
			const d = result.details as PruneDetails | undefined;
			if (!d) return new Text("", 0, 0);
			return new Text(theme.fg("success", `✓ recalled ${d.applied.length}`) + theme.fg("dim", ` (${d.total} forgotten)`), 0, 0);
		},
	});
}
