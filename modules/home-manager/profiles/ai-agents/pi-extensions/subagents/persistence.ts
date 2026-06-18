/**
 * Subagents persistence — thin fs shell around persistence-logic.ts (kept SDK-free).
 * Layout: <mainSessionDir>/subagents/<mainSessionId>/{roster.json, <id>.jsonl}.
 * Design: docs/superpowers/specs/2026-06-18-subagents-history-persistence-design.md
 */
import * as fs from "node:fs";
import * as path from "node:path";
import { parseRoster, type RosterEntry, serializeRoster } from "./persistence-logic.ts";

export type { RosterEntry } from "./persistence-logic.ts";

/** Directory holding one main session's subagent files. Nested so pi's session pickers
 * (which scan <encoded-cwd>/*.jsonl non-recursively) never list these. */
export function subagentsDir(mainSessionDir: string, mainSessionId: string): string {
	return path.join(mainSessionDir, "subagents", mainSessionId);
}

/** Overwrite roster.json with the current background membership (spawn/kill triggers). */
export function writeRoster(dir: string, agents: Parameters<typeof serializeRoster>[0]): void {
	fs.mkdirSync(dir, { recursive: true });
	fs.writeFileSync(path.join(dir, "roster.json"), JSON.stringify(serializeRoster(agents), null, 2));
}

/** Read + validate roster.json; [] when absent or malformed. */
export function readRoster(dir: string): RosterEntry[] {
	try {
		return parseRoster(fs.readFileSync(path.join(dir, "roster.json"), "utf8"));
	} catch {
		return [];
	}
}
