/**
 * Pure formatting for the read-only observability of the agents.
 * No pi/TUI dependency; the strings are rendered into the UI in index.ts.
 */
import { statusLabel, type AgentRecord, type AgentEvent } from "./engine.ts";

/** Compact relative age: 3s / 4m / 2h. */
function formatAge(ms: number): string {
	const s = Math.floor(Math.max(0, ms) / 1000);
	if (s < 60) return `${s}s`;
	const m = Math.floor(s / 60);
	if (m < 60) return `${m}m`;
	return `${Math.floor(m / 60)}h`;
}

/** Relation of an agent to the viewer, for orientation in deep hierarchies. */
function relTo(a: AgentRecord, viewer: string, viewerParent: string | undefined): string {
	if (a.name === viewer) return "self";
	if (a.spawnedBy === viewer) return "child";
	if (a.name === viewerParent) return "parent";
	if (viewerParent !== undefined && a.spawnedBy === viewerParent) return "peer";
	return "other";
}

/**
 * Roster as seen by `viewer` (the calling agent). Surfaces live health/progress
 * signals (spawning vs idle, context pressure, staleness) and the relation to the
 * viewer so an agent can decide: message, wait, or wind down. `now` is injected
 * for testability.
 */
export function formatSnapshot(
	agents: AgentRecord[],
	turnsUsed: number,
	turnBudget: number,
	viewer: string,
	now: number = Date.now(),
): string {
	if (agents.length === 0) return "no agents";
	const viewerParent = agents.find((a) => a.name === viewer)?.spawnedBy;
	const rows = agents.map((a) => {
		const status = statusLabel(a);
		const u = a.view?.getContextUsage();
		const ctx = u && u.percent != null ? `${Math.round(u.percent)}%` : "--";
		const rel = relTo(a, viewer, viewerParent);
		const queued = a.pending && a.buffer && a.buffer.length > 0 ? `, ${a.buffer.length} queued` : "";
		return (
			`  ${a.name.padEnd(14)} ${rel.padEnd(6)} ${status.padEnd(12)} ` +
			`turns:${String(a.turns).padEnd(3)} ctx:${ctx.padEnd(4)} last ${formatAge(now - a.lastActivity).padEnd(4)} ` +
			`${a.model}  (by ${a.spawnedBy}${queued})`
		);
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
