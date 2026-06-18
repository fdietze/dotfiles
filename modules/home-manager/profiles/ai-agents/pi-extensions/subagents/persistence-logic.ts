/**
 * Pure persistence helpers — no pi/SDK/fs dependency, fully testable.
 * Message-shape logic for restoring subagent sessions from disk and serializing the
 * membership roster. Shapes mirror panel-logic.ts (assistant content = part array with
 * {type:"toolCall", id, name}; toolResult message = {role, toolCallId}).
 * Design: docs/superpowers/specs/2026-06-18-subagents-history-persistence-design.md
 */

export interface RawMessage {
	role?: string;
	content?: unknown;
	toolCallId?: string;
	stopReason?: string;
}

interface ToolCallPart {
	type?: string;
	id?: string;
	name?: string;
}

/** Tool-call {id,name} parts of an assistant message (empty for non-assistant). */
function assistantToolCalls(m: RawMessage): { id: string; name: string }[] {
	if (m.role !== "assistant" || !Array.isArray(m.content)) return [];
	return (m.content as ToolCallPart[])
		.filter((p) => p?.type === "toolCall" && typeof p.id === "string")
		.map((p) => ({ id: p.id as string, name: p.name ?? "tool" }));
}

/** Index of the last assistant message, or -1. */
function lastAssistantIndex(messages: RawMessage[]): number {
	for (let i = messages.length - 1; i >= 0; i--) {
		if (messages[i]?.role === "assistant") return i;
	}
	return -1;
}

/**
 * Tool-call ids of the LAST assistant message that have no matching `toolResult`
 * after it. A crash between persisting an assistant tool_use and its tool_result
 * leaves such danglers; the provider rejects a tool_use without a tool_result, so the
 * caller must synthesize a result for each before resuming.
 */
export function danglingToolResultIds(messages: RawMessage[]): { id: string; name: string }[] {
	const idx = lastAssistantIndex(messages);
	if (idx === -1) return [];
	const calls = assistantToolCalls(messages[idx]);
	if (calls.length === 0) return [];
	const resolved = new Set<string>();
	for (let i = idx + 1; i < messages.length; i++) {
		const m = messages[i];
		if (m?.role === "toolResult" && typeof m.toolCallId === "string") resolved.add(m.toolCallId);
	}
	return calls.filter((c) => !resolved.has(c.id));
}

/**
 * Derive an agent's restored status from its transcript tail.
 * idle = the agent finished its turn: the last message is an assistant answer with no
 * tool calls and a normal stop reason. Everything else means it was mid-turn (trailing
 * toolResult the model still owes a reply to, dangling tool calls, or aborted/error) →
 * halted, so resume re-triggers it.
 */
export function deriveStatus(messages: RawMessage[]): "idle" | "halted" {
	if (messages.length === 0) return "idle";
	const last = messages[messages.length - 1];
	if (
		last?.role === "assistant" &&
		assistantToolCalls(last).length === 0 &&
		last.stopReason !== "aborted" &&
		last.stopReason !== "error"
	) {
		return "idle";
	}
	return "halted";
}

export interface RosterEntry {
	name: string;
	spawnedBy: string;
	depth: number;
	model: string;
	systemPrompt: string;
	sessionFile: string;
}

/** Roster entries from engine records; only agents with a real session file persist. */
export function serializeRoster(
	agents: Array<{
		name: string;
		spawnedBy: string;
		depth: number;
		model: string;
		systemPrompt?: string;
		sessionFile?: string;
	}>,
): RosterEntry[] {
	return agents
		.filter((a) => a.name !== "main" && typeof a.sessionFile === "string")
		.map((a) => ({
			name: a.name,
			spawnedBy: a.spawnedBy,
			depth: a.depth,
			model: a.model,
			systemPrompt: a.systemPrompt ?? "",
			sessionFile: a.sessionFile as string,
		}));
}

/** Parse + validate roster JSON; drops malformed entries, returns [] on any error. */
export function parseRoster(json: string): RosterEntry[] {
	let data: unknown;
	try {
		data = JSON.parse(json);
	} catch {
		return [];
	}
	if (!Array.isArray(data)) return [];
	return data.filter(
		(e): e is RosterEntry =>
			!!e &&
			typeof e.name === "string" &&
			typeof e.spawnedBy === "string" &&
			typeof e.depth === "number" &&
			typeof e.model === "string" &&
			typeof e.systemPrompt === "string" &&
			typeof e.sessionFile === "string",
	);
}
