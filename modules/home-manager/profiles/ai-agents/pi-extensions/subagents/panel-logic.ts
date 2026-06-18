/** Pure helpers for the subagents panel — no pi/TUI dependency, fully testable. */

export interface ContextUsageLike {
	tokens: number | null;
	contextWindow: number;
	percent: number | null;
}

const k = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}k` : `${n}`);

export function formatContext(u: ContextUsageLike | undefined): string {
	if (!u || u.tokens === null) return "—";
	// Fixed field widths so the display does not jump as the numbers grow.
	// pi's ContextUsage.percent is already a percentage (0–100), not a fraction.
	// Compact form "  15k/200k ( 7%)" — no separator, padded for stable column alignment.
	const used = k(u.tokens).padStart(5);
	const total = k(u.contextWindow).padEnd(4);
	if (u.percent === null) return `${used}/${total}`;
	const pct = `${Math.round(u.percent)}%`.padStart(3);
	return `${used}/${total} (${pct})`;
}

/** Send targets of an agent from the message matrix, ordered by count desc (alpha tiebreak). */
export function sendTargets(
	matrix: Record<string, Record<string, number>>,
	name: string,
): { to: string; count: number }[] {
	const row = matrix[name];
	if (!row) return [];
	return Object.entries(row)
		.map(([to, count]) => ({ to, count }))
		.sort((a, b) => b.count - a.count || a.to.localeCompare(b.to));
}

/** Roster cell of send targets: "→main·3 coder·1" (most-messaged first); "" when none. */
export function formatSendTargets(matrix: Record<string, Record<string, number>>, name: string): string {
	const t = sendTargets(matrix, name);
	if (t.length === 0) return "";
	return `→${t.map((x) => `${x.to}·${x.count}`).join(" ")}`;
}

export interface RosterEntry {
	name: string;
	model: string;
	context: string;
	/** Display status from engine.statusLabel (spawning/thinking/writing/tool:.../idle). */
	status: string;
	/** Send targets cell (formatSendTargets); appended in full, never truncated. */
	targets?: string;
}

/**
 * Swarm-wide scheduler state line, shown below the roster (panel) and footer. Expresses
 * the mode that /halt and /unhalt toggle (halted vs live) plus the real activity count,
 * so it never claims "running" while every agent is idle. The fine-grained per-agent phase
 * (thinking/tool:.../idle) lives in the rows; this line is only the global mode.
 */
export function swarmStateLine(frozen: boolean, runningCount: number): string {
	if (frozen) return " ⏸ halted — /unhalt to resume ";
	return ` ▶ live · ${runningCount > 0 ? `${runningCount} working` : "idle"} `;
}

/** Status column width; fits "thinking"/"spawning" and short "tool:bash" labels. */
const STATUS_COL = 10;
/**
 * A status counts as "busy" (active-work highlight) unless the agent is idle, still
 * spawning, or halted. halted is a stopped state (awaiting resume), so it gets the same
 * subtle styling as idle rather than the active-work highlight.
 */
export function isBusy(status: string): boolean {
	return status !== "idle" && status !== "spawning" && status !== "halted";
}

/** Short model id for the roster: drop the "provider/" prefix, truncate to fit. */
const MODEL_COL = 16;
export function shortModel(model: string | undefined): string {
	if (!model) return "";
	const id = model.includes("/") ? model.slice(model.lastIndexOf("/") + 1) : model;
	return id.length > MODEL_COL ? `${id.slice(0, MODEL_COL - 1)}…` : id;
}

export function formatRosterRow(
	entry: RosterEntry,
	selected: boolean,
	width: number,
	// Optional styler for the status label (background color when busy). Default: identity.
	styleStatus: (label: string, busy: boolean) => string = (l) => l,
): string {
	// Layout: <cursor> <status> <name> <context>. Status as a fixed ASCII column at the
	// front (robustly aligned, independent of the variable context width at the end).
	const cursor = selected ? "▸" : " ";
	const busy = isBusy(entry.status);
	const label =
		entry.status.length > STATUS_COL ? `${entry.status.slice(0, STATUS_COL - 1)}…` : entry.status.padEnd(STATUS_COL);
	const name = entry.name.length > 14 ? `${entry.name.slice(0, 13)}…` : entry.name.padEnd(14);
	const model = shortModel(entry.model).padEnd(MODEL_COL);
	// Fixed-width base columns; the variable send-targets cell is appended in full (not
	// capped to width — long target lists wrap rather than hide who an agent talks to).
	const base = `${cursor} ${label} ${name} ${model} ${entry.context}`;
	// Degenerate guard: only the fixed base is bounded by width (it always fits in practice).
	if (base.length > width) return base.slice(0, width);
	const styledBase = `${cursor} ${styleStatus(label, busy)} ${name} ${model} ${entry.context}`;
	return entry.targets ? `${styledBase}  ${entry.targets}` : styledBase;
}

export function moveSelection(current: number, delta: number, count: number): number {
	if (count <= 0) return 0;
	const next = current + delta;
	if (next < 0) return 0;
	if (next > count - 1) return count - 1;
	return next;
}

/** Clamp offset so [offset, offset+viewport) stays valid; clamp to [0, max]. */
export function clampScroll(offset: number, total: number, viewport: number): number {
	const max = Math.max(0, total - viewport);
	if (offset < 0) return 0;
	if (offset > max) return max;
	return offset;
}

/** Extract plain text from message.content (string or part array). */
export function messageText(content: unknown): string {
	if (typeof content === "string") return content;
	if (Array.isArray(content)) {
		return (content as { type?: string; text?: string }[])
			.filter((p) => p?.type === "text")
			.map((p) => p.text ?? "")
			.join("");
	}
	return "";
}

/** Tool-call names from an assistant message as "⚙ name" labels. */
export interface ToolCallPart {
	id: string;
	name: string;
	arguments: unknown;
}

/** Extract tool calls from an assistant message (id/name/arguments). */
export function toolCalls(m: { role?: string; content?: unknown }): ToolCallPart[] {
	if (m.role === "assistant" && Array.isArray(m.content)) {
		return (m.content as { type?: string; id?: string; name?: string; arguments?: unknown }[])
			.filter((p) => p?.type === "toolCall")
			.map((p) => ({ id: p.id ?? "", name: p.name ?? "tool", arguments: p.arguments }));
	}
	return [];
}

/** Find the matching toolResult for a toolCall id (inline rendering like the main chat). */
export function findToolResult(
	msgs: { role?: string; toolCallId?: string }[],
	id: string,
): { role?: string; toolCallId?: string } | undefined {
	return msgs.find((m) => m.role === "toolResult" && m.toolCallId === id);
}

/**
 * Append the in-progress streaming assistant message for live rendering, unless the
 * session already holds it (identity match on the last entry) — avoids double-render.
 */
export function mergeStreaming<T>(msgs: T[], streamingMessage: T | undefined): T[] {
	if (!streamingMessage) return msgs;
	if (msgs.length > 0 && msgs[msgs.length - 1] === streamingMessage) return msgs;
	return [...msgs, streamingMessage];
}

export function chatboxToRoute(selected: string | undefined, text: string): { to: string; content: string } | null {
	if (!selected) return null;
	const content = text.trim();
	if (!content) return null;
	return { to: selected, content };
}
