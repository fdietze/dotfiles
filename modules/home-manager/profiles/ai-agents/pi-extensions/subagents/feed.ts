/**
 * Reine Formatierung für die read-only Beobachtbarkeit der Agents.
 * Keine pi-/TUI-Abhängigkeit; die Strings werden in index.ts in UI gerendert.
 */
import type { AgentRecord, AgentEvent } from "./engine.ts";

export function formatStatus(agentCount: number, runningCount: number, turnsUsed: number, turnBudget: number): string {
	return `${agentCount} agents · ${runningCount} running · budget ${turnsUsed}/${turnBudget}`;
}

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
		}
	});
}

/** Normalisiert das `to`-Feld (Name oder Liste) zu einer deduplizierten Namensliste. */
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

/** Fasst ein Multicast-Ergebnis kompakt zusammen (für die Tool-Antwort). */
export function formatMulticastResult(results: MulticastOutcome[]): string {
	if (results.length === 0) return "error: no targets";
	const delivered = results.filter((r) => r.ok).map((r) => r.target);
	const failed = results.filter((r) => !r.ok).map((r) => `${r.target}: ${r.reason}`);
	const parts: string[] = [];
	if (delivered.length) parts.push(`sent to ${delivered.join(", ")}`);
	if (failed.length) parts.push(`failed: ${failed.join("; ")}`);
	return parts.join(" · ");
}

/** Fasst ein Kill-Ergebnis kompakt zusammen (für die Tool-Antwort). */
export function formatKillResult(results: MulticastOutcome[]): string {
	if (results.length === 0) return "error: no targets";
	const killed = results.filter((r) => r.ok).map((r) => r.target);
	const failed = results.filter((r) => !r.ok).map((r) => `${r.target}: ${r.reason}`);
	const parts: string[] = [];
	if (killed.length) parts.push(`killed ${killed.join(", ")}`);
	if (failed.length) parts.push(`failed: ${failed.join("; ")}`);
	return parts.join(" · ");
}
