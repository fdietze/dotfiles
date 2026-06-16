/** Pure Helfer fürs Swarm-Panel — keine pi/TUI-Abhängigkeit, voll testbar. */

export interface ContextUsageLike {
	tokens: number | null;
	contextWindow: number;
	percent: number | null;
}

const k = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}k` : `${n}`);

export function formatContext(u: ContextUsageLike | undefined): string {
	if (!u || u.tokens === null) return "—";
	// Feste Feldbreiten, damit die Anzeige beim Wachsen der Zahlen nicht springt.
	// pi's ContextUsage.percent ist bereits ein Prozentwert (0–100), nicht ein Bruch.
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
	// Optionaler Styler für das Status-Label (Hintergrundfarbe für active). Default: identisch.
	styleStatus: (label: string, active: boolean) => string = (l) => l,
): string {
	// Layout: <cursor> <status> <name> <context>. Status als feste ASCII-Spalte ganz
	// vorne (robust ausgerichtet, unabhängig von der variablen Kontextbreite am Ende).
	const cursor = selected ? "▸" : " ";
	const label = (entry.active ? "active" : "idle").padEnd(6);
	const name = entry.name.length > 14 ? `${entry.name.slice(0, 13)}…` : entry.name.padEnd(14);
	const plain = `${cursor} ${label} ${name} ${entry.context}`;
	// Breiten-Logik auf dem ungefärbten String (ANSI würde .length verfälschen).
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

/** offset so dass [offset, offset+viewport) gültig bleibt; clamp auf [0, max]. */
export function clampScroll(offset: number, total: number, viewport: number): number {
	const max = Math.max(0, total - viewport);
	if (offset < 0) return 0;
	if (offset > max) return max;
	return offset;
}

/** Reinen Text aus message.content ziehen (string oder Part-Array). */
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

/** Tool-Call-Namen aus einer Assistant-Nachricht als "⚙ name"-Labels. */
export interface ToolCallPart {
	id: string;
	name: string;
	arguments: unknown;
}

/** Tool-Calls aus einer Assistant-Message ziehen (id/name/arguments). */
export function toolCalls(m: { role?: string; content?: unknown }): ToolCallPart[] {
	if (m.role === "assistant" && Array.isArray(m.content)) {
		return (m.content as { type?: string; id?: string; name?: string; arguments?: unknown }[])
			.filter((p) => p?.type === "toolCall")
			.map((p) => ({ id: p.id ?? "", name: p.name ?? "tool", arguments: p.arguments }));
	}
	return [];
}

/** Passendes toolResult zu einer toolCall-id finden (Inline-Rendering wie im Haupt-Chat). */
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
