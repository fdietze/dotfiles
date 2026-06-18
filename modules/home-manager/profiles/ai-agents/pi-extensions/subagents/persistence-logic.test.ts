import assert from "node:assert/strict";
import { test } from "node:test";
import {
	danglingToolResultIds,
	deriveStatus,
	parseRoster,
	type RawMessage,
	serializeRoster,
} from "./persistence-logic.ts";

const assistant = (calls: { id: string; name?: string }[], stopReason?: string): RawMessage => ({
	role: "assistant",
	content: [
		{ type: "text", text: "..." },
		...calls.map((c) => ({ type: "toolCall", id: c.id, name: c.name ?? "bash" })),
	],
	stopReason,
});
const toolResult = (id: string): RawMessage => ({ role: "toolResult", toolCallId: id });
const user = (): RawMessage => ({ role: "user", content: "hi" });

test("danglingToolResultIds: trailing single tool call, no result -> dangling", () => {
	const msgs = [user(), assistant([{ id: "t1" }])];
	assert.deepEqual(danglingToolResultIds(msgs), [{ id: "t1", name: "bash" }]);
});

test("danglingToolResultIds: matched result -> none", () => {
	const msgs = [user(), assistant([{ id: "t1" }]), toolResult("t1")];
	assert.deepEqual(danglingToolResultIds(msgs), []);
});

test("danglingToolResultIds: parallel calls, partial results -> only unmatched", () => {
	const msgs = [assistant([{ id: "a" }, { id: "b" }, { id: "c", name: "read" }]), toolResult("b")];
	assert.deepEqual(danglingToolResultIds(msgs), [
		{ id: "a", name: "bash" },
		{ id: "c", name: "read" },
	]);
});

test("danglingToolResultIds: clean answer / no trailing assistant -> none", () => {
	assert.deepEqual(danglingToolResultIds([user(), assistant([])]), []);
	assert.deepEqual(danglingToolResultIds([user()]), []);
	assert.deepEqual(danglingToolResultIds([]), []);
});

test("deriveStatus: clean assistant answer -> idle", () => {
	assert.equal(deriveStatus([user(), assistant([])]), "idle");
});

test("deriveStatus: empty -> idle", () => {
	assert.equal(deriveStatus([]), "idle");
});

test("deriveStatus: trailing tool_use -> halted", () => {
	assert.equal(deriveStatus([assistant([{ id: "t1" }])]), "halted");
});

test("deriveStatus: trailing toolResult (model owes reply) -> halted", () => {
	assert.equal(deriveStatus([assistant([{ id: "t1" }]), toolResult("t1")]), "halted");
});

test("deriveStatus: aborted/error stop reason -> halted", () => {
	assert.equal(deriveStatus([assistant([], "aborted")]), "halted");
	assert.equal(deriveStatus([assistant([], "error")]), "halted");
});

test("roster round-trip serialize -> parse", () => {
	const agents = [
		{ name: "main", spawnedBy: "main", depth: 0, model: "x/y", sessionFile: "/m" },
		{ name: "a", spawnedBy: "main", depth: 1, model: "p/q", systemPrompt: "do x", sessionFile: "/a.jsonl" },
		{ name: "pending", spawnedBy: "main", depth: 1, model: "(spawning)" }, // no sessionFile -> dropped
	];
	const roster = serializeRoster(agents);
	assert.equal(roster.length, 1);
	assert.equal(roster[0].name, "a");
	const json = JSON.stringify(roster);
	assert.deepEqual(parseRoster(json), roster);
});

test("parseRoster: malformed -> []", () => {
	assert.deepEqual(parseRoster("not json"), []);
	assert.deepEqual(parseRoster("{}"), []);
	assert.deepEqual(parseRoster('[{"name":"a"}]'), []); // missing required fields
});
