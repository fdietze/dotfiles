import { test } from "node:test";
import assert from "node:assert/strict";
import {
	formatStatus,
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
	spawnedBy: "user",
	depth: 1,
	createdAt: 0,
	turns: 0,
	lastActivity: 0,
	streaming: false,
	...over,
});

test("formatStatus summarises counts and budget", () => {
	const s = formatStatus(3, 1, 7, 100);
	assert.match(s, /3 agents/);
	assert.match(s, /1 running/);
	assert.match(s, /7\/100/);
});

test("formatSnapshot lists each agent with status and turns", () => {
	const agents = [
		rec({ name: "user", depth: 0, model: "anthropic/opus" }),
		rec({ name: "coder", streaming: true, turns: 4 }),
	];
	const out = formatSnapshot(agents, 4, 100);
	assert.match(out, /user/);
	assert.match(out, /coder/);
	assert.match(out, /running/);
	assert.match(out, /idle/);
	assert.match(out, /4/);
});

test("formatFeedLines renders one line per event newest-aware", () => {
	const events: AgentEvent[] = [
		{ type: "spawn", name: "coder", by: "user", ts: 0 },
		{ type: "route", from: "user", to: "coder", preview: "do x", ts: 0 },
		{ type: "halt", ts: 0 },
	];
	const lines = formatFeedLines(events);
	assert.equal(lines.length, 3);
	assert.match(lines[0], /spawn.*coder/);
	assert.match(lines[1], /user.*->.*coder/);
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
			{ target: "user", ok: false, reason: "cannot kill 'user'" },
		]),
		"killed a · failed: user: cannot kill 'user'",
	);
	assert.equal(formatKillResult([]), "error: no targets");
});
