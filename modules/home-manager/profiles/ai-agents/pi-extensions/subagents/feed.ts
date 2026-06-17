/**
 * Pure formatting for the read-only observability of the agents.
 * No pi/TUI dependency; the strings are rendered into the UI in index.ts.
 */
import type { AgentRecord, AgentEvent } from "./engine.ts";

export function formatSnapshot(agents: AgentRecord[], turnsUsed: number, turnBudget: number): string {
	if (agents.length === 0) return "no agents";
	const rows = agents.map((a) => {
		const status = a.streaming ? "running" : "idle";
		return `  ${a.name.padEnd(14)} ${status.padEnd(8)} turns:${a.turns}  ${a.model}  (by ${a.spawnedBy}, depth ${a.depth})`;
	});
	return [`agents (budget ${turnsUsed}/${turnBudget}):`, ...rows].join("\n");
}

export function formatFeedLines(events: AgentEvent[]): string[] {
	return events.map((e) => {
		switch (e.type) {
			case "spawn":
				return `spawn   ${e.name} (by ${e.by})`;
			case "route":
				return `route   ${e.from} -> ${e.to}: ${e.preview}`;
			case "turn":
				return `turn    ${e.name}`;
			case "halt":
				return `HALT`;
			case "resume":
				return `RESUME`;
			case "kill":
				return `kill    ${e.name}`;
			case "blocked":
				return `blocked ${e.reason}`;
			case "error":
				return `error   ${e.name}: ${e.reason}`;
		}
	});
}

/** Normalizes the `to` field (name or list) into a deduplicated list of names. */
export function normalizeTargets(to: string | string[]): string[] {
	const arr = Array.isArray(to) ? to : [to];
	const seen = new Set<string>();
	const out: string[] = [];
	for (const raw of arr) {
		const name = raw.trim();
		if (name && !seen.has(name)) {
			seen.add(name);
			out.push(name);
		}
	}
	return out;
}

export interface MulticastOutcome {
	target: string;
	ok: boolean;
	reason?: string;
}

/** Summarizes a multicast result compactly (for the tool response). */
export function formatMulticastResult(results: MulticastOutcome[]): string {
	if (results.length === 0) return "error: no targets";
	const delivered = results.filter((r) => r.ok).map((r) => r.target);
	const failed = results.filter((r) => !r.ok).map((r) => `${r.target}: ${r.reason}`);
	const parts: string[] = [];
	if (delivered.length) parts.push(`sent to ${delivered.join(", ")}`);
	if (failed.length) parts.push(`failed: ${failed.join("; ")}`);
	return parts.join(" · ");
}

/** Summarizes a kill result compactly (for the tool response). */
export function formatKillResult(results: MulticastOutcome[]): string {
	if (results.length === 0) return "error: no targets";
	const killed = results.filter((r) => r.ok).map((r) => r.target);
	const failed = results.filter((r) => !r.ok).map((r) => `${r.target}: ${r.reason}`);
	const parts: string[] = [];
	if (killed.length) parts.push(`killed ${killed.join(", ")}`);
	if (failed.length) parts.push(`failed: ${failed.join("; ")}`);
	return parts.join(" · ");
}
