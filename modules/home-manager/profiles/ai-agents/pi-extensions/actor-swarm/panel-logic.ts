/** Pure Helfer fürs Swarm-Panel — keine pi/TUI-Abhängigkeit, voll testbar. */

export interface ContextUsageLike {
	tokens: number | null;
	contextWindow: number;
	percent: number | null;
}

const k = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}k` : `${n}`);

export function formatContext(u: ContextUsageLike | undefined): string {
	if (!u || u.tokens === null) return "—";
	// pi's ContextUsage.percent ist bereits ein Prozentwert (0–100), nicht ein Bruch.
	const pct = u.percent === null ? "" : ` · ${Math.round(u.percent)}%`;
	return `${k(u.tokens)}/${k(u.contextWindow)}${pct}`;
}

export interface RosterEntry {
	name: string;
	context: string;
	active: boolean;
}

export function formatRosterRow(entry: RosterEntry, selected: boolean, width: number): string {
	const cursor = selected ? "▸ " : "  ";
	const status = entry.active ? "●active" : " idle";
	const line = `${cursor}${entry.name.padEnd(12)} ${entry.context.padEnd(16)} ${status}`;
	return line.length > width ? line.slice(0, width) : line;
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
export function toolCallLabels(m: { role?: string; content?: unknown }): string[] {
	if (m.role === "assistant" && Array.isArray(m.content)) {
		return (m.content as { type?: string; name?: string }[])
			.filter((p) => p?.type === "toolCall")
			.map((p) => `⚙ ${p.name ?? "tool"}`);
	}
	return [];
}

export function chatboxToRoute(selected: string | undefined, text: string): { to: string; content: string } | null {
	if (!selected) return null;
	const content = text.trim();
	if (!content) return null;
	return { to: selected, content };
}
