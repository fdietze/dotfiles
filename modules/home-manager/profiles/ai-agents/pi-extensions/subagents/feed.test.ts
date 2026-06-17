import { test } from "node:test";
import assert from "node:assert/strict";
import {
	formatSnapshot,
	formatFeedLines,
	normalizeTargets,
	formatMulticastResult,
	formatKillResult,
} from "./feed.ts";
import type { AgentRecord, AgentEvent } from "./engine.ts";

const rec = (over: Partial<AgentRecord>): AgentRecord => ({
	name: "a",
	model: "anthropic/x",
	handle: { deliver: async () => {}, abort: async () => {}, isStreaming: () => false },
	spawnedBy: "main",
	depth: 1,
	createdAt: 0,
	turns: 0,
	lastActivity: 0,
	streaming: false,
	...over,
});

test("formatSnapshot lists each agent with status and turns", () => {
	const agents = [
		rec({ name: "main", depth: 0, model: "anthropic/opus" }),
		rec({ name: "coder", streaming: true, turns: 4 }),
	];
	const out = formatSnapshot(agents, 4, 100, "main");
	assert.match(out, /main/);
	assert.match(out, /coder/);
	assert.match(out, /thinking/); // streaming, no fine-grained activity yet
	assert.match(out, /idle/);
	assert.match(out, /4/);
});

test("formatSnapshot renders fine-grained activity (writing / tool:name)", () => {
	const agents = [
		rec({ name: "w", streaming: true, activity: "writing" }),
		rec({ name: "t", streaming: true, activity: "tool", currentTool: "bash" }),
	];
	const out = formatSnapshot(agents, 0, 100, "main");
	assert.match(out, /writing/);
	assert.match(out, /tool:bash/);
});

test("formatSnapshot shows pending agents as spawning (not idle) with queue count", () => {
	const agents = [rec({ name: "coder", pending: true, buffer: ["a", "b"] })];
	const out = formatSnapshot(agents, 0, 100, "main");
	assert.match(out, /spawning/);
	assert.doesNotMatch(out, /idle/);
	assert.match(out, /2 queued/);
});

test("formatSnapshot marks relation to the viewer", () => {
	// tree: main -> lead -> worker ; viewer = lead
	const agents = [
		rec({ name: "main", depth: 0, spawnedBy: "main" }),
		rec({ name: "lead", spawnedBy: "main" }),
		rec({ name: "sibling", spawnedBy: "main" }),
		rec({ name: "worker", spawnedBy: "lead" }),
	];
	const out = formatSnapshot(agents, 0, 100, "lead");
	assert.match(out, /lead .*self/);
	assert.match(out, /main .*parent/);
	assert.match(out, /sibling .*peer/);
	assert.match(out, /worker .*child/);
});

test("formatSnapshot shows context percent and relative age", () => {
	const withCtx = rec({
		name: "coder",
		lastActivity: 5_000,
		view: {
			getMessages: () => [],
			getContextUsage: () => ({ tokens: 100, contextWindow: 1000, percent: 42 }),
			subscribe: () => () => {},
		},
	});
	const out = formatSnapshot([withCtx], 0, 100, "main", 10_000);
	assert.match(out, /ctx:42%/);
	assert.match(out, /last 5s/);
});

test("formatFeedLines renders one line per event newest-aware", () => {
	const events: AgentEvent[] = [
		{ type: "spawn", name: "coder", by: "main", ts: 0 },
		{ type: "route", from: "main", to: "coder", preview: "do x", ts: 0 },
		{ type: "halt", ts: 0 },
		{ type: "error", name: "coder", reason: "boom", ts: 0 },
	];
	const lines = formatFeedLines(events);
	assert.equal(lines.length, 4);
	assert.match(lines[0], /spawn.*coder/);
	assert.match(lines[1], /main.*->.*coder/);
	assert.match(lines[2], /halt/i);
	assert.match(lines[3], /error.*coder.*boom/);
});

test("normalizeTargets: single, list, dedupe, trim, drop empty", () => {
	assert.deepEqual(normalizeTargets("echo"), ["echo"]);
	assert.deepEqual(normalizeTargets(["echo", "planner"]), ["echo", "planner"]);
	assert.deepEqual(normalizeTargets(["a", "a", " b ", ""]), ["a", "b"]);
});

test("formatMulticastResult: delivered + failed split", () => {
	assert.equal(formatMulticastResult([{ target: "a", ok: true }]), "sent to a");
	assert.match(
		formatMulticastResult([
			{ target: "a", ok: true },
			{ target: "x", ok: false, reason: "unknown agent 'x'" },
		]),
		/sent to a · failed: x: unknown agent 'x'/,
	);
	assert.equal(formatMulticastResult([]), "error: no targets");
});

test("formatKillResult: killed + failed split", () => {
	assert.equal(formatKillResult([{ target: "a", ok: true }]), "killed a");
	assert.equal(
		formatKillResult([
			{ target: "a", ok: true },
			{ target: "main", ok: false, reason: "cannot kill 'main'" },
		]),
		"killed a · failed: main: cannot kill 'main'",
	);
	assert.equal(formatKillResult([]), "error: no targets");
});
