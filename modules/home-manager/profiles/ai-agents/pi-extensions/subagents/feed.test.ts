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
	const out = formatSnapshot(agents, 4, 100);
	assert.match(out, /main/);
	assert.match(out, /coder/);
	assert.match(out, /running/);
	assert.match(out, /idle/);
	assert.match(out, /4/);
});

test("formatFeedLines renders one line per event newest-aware", () => {
	const events: AgentEvent[] = [
		{ type: "spawn", name: "coder", by: "main", ts: 0 },
		{ type: "route", from: "main", to: "coder", preview: "do x", ts: 0 },
		{ type: "halt", ts: 0 },
	];
	const lines = formatFeedLines(events);
	assert.equal(lines.length, 3);
	assert.match(lines[0], /spawn.*coder/);
	assert.match(lines[1], /main.*->.*coder/);
	assert.match(lines[2], /halt/i);
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
