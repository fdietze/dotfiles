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
	const used = k(u.tokens).padStart(5);
	const total = k(u.contextWindow);
	if (u.percent === null) return `${used}/${total}`;
	const pct = `${Math.round(u.percent)}%`.padStart(4);
	return `${used}/${total} · ${pct}`;
}

export interface RosterEntry {
	name: string;
	context: string;
	active: boolean;
}

export function formatRosterRow(
	entry: RosterEntry,
	selected: boolean,
	width: number,
	// Optional styler for the status label (background color for active). Default: identity.
	styleStatus: (label: string, active: boolean) => string = (l) => l,
): string {
	// Layout: <cursor> <status> <name> <context>. Status as a fixed ASCII column at the
	// front (robustly aligned, independent of the variable context width at the end).
	const cursor = selected ? "▸" : " ";
	const label = (entry.active ? "active" : "idle").padEnd(6);
	const name = entry.name.length > 14 ? `${entry.name.slice(0, 13)}…` : entry.name.padEnd(14);
	const plain = `${cursor} ${label} ${name} ${entry.context}`;
	// Width logic on the uncolored string (ANSI would corrupt .length).
	if (plain.length > width) return plain.slice(0, width);
	return `${cursor} ${styleStatus(label, entry.active)} ${name} ${entry.context}`;
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

export function chatboxToRoute(selected: string | undefined, text: string): { to: string; content: string } | null {
	if (!selected) return null;
	const content = text.trim();
	if (!content) return null;
	return { to: selected, content };
}
