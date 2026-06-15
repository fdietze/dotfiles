/**
 * Reine Formatierung für die read-only Beobachtbarkeit des Swarms.
 * Keine pi-/TUI-Abhängigkeit; die Strings werden in index.ts in UI gerendert.
 */
import type { ActorRecord, SwarmEvent } from "./engine.ts";

export function formatStatus(actorCount: number, runningCount: number, turnsUsed: number, turnBudget: number): string {
	return `swarm: ${actorCount} actors · ${runningCount} running · budget ${turnsUsed}/${turnBudget}`;
}

export function formatSnapshot(actors: ActorRecord[], turnsUsed: number, turnBudget: number): string {
	if (actors.length === 0) return "no actors";
	const rows = actors.map((a) => {
		const status = a.streaming ? "running" : "idle";
		return `  ${a.name.padEnd(14)} ${status.padEnd(8)} turns:${a.turns}  ${a.model}  (by ${a.spawnedBy}, depth ${a.depth})`;
	});
	return [`actors (budget ${turnsUsed}/${turnBudget}):`, ...rows].join("\n");
}

export function formatFeedLines(events: SwarmEvent[]): string[] {
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
			case "blocked":
				return `blocked ${e.reason}`;
		}
	});
}
