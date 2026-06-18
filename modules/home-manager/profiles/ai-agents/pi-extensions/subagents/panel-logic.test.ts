import { test } from "node:test";
import assert from "node:assert/strict";
import {
	formatContext,
	formatRosterRow,
	moveSelection,
	clampScroll,
	chatboxToRoute,
	messageText,
	toolCalls,
	findToolResult,
	shortModel,
	mergeStreaming,
	isBusy,
	swarmStateLine,
	sendTargets,
	formatSendTargets,
} from "./panel-logic.ts";

test("formatContext renders tokens/window/percent (percent is already 0-100), dash when unknown", () => {
	// pi's ContextUsage.percent is already a percentage (footer.js uses it directly).
	assert.match(formatContext({ tokens: 12000, contextWindow: 200000, percent: 6 }), /12k\/200k.*6%/);
	assert.match(formatContext({ tokens: 124000, contextWindow: 200000, percent: 62 }), /62%/);
	assert.equal(formatContext({ tokens: null, contextWindow: 200000, percent: null }), "—");
	assert.equal(formatContext(undefined), "—");
	// Compact form: no separator, percent in parentheses.
	const c = formatContext({ tokens: 15000, contextWindow: 200000, percent: 7 });
	assert.match(c, /15k\/200k \( ?7%\)/);
	assert.doesNotMatch(c, /·/);
});

test("sendTargets: ordered by count desc, alpha tiebreak; empty when none", () => {
	const matrix = { a: { main: 3, coder: 3, zed: 1 }, b: {} };
	assert.deepEqual(sendTargets(matrix, "a"), [
		{ to: "coder", count: 3 },
		{ to: "main", count: 3 },
		{ to: "zed", count: 1 },
	]);
	assert.deepEqual(sendTargets(matrix, "b"), []);
	assert.deepEqual(sendTargets(matrix, "missing"), []);
});

test("formatSendTargets: arrow + name·count, most-messaged first; '' when none", () => {
	const matrix = { a: { main: 3, coder: 1 } };
	assert.equal(formatSendTargets(matrix, "a"), "→main·3 coder·1");
	assert.equal(formatSendTargets(matrix, "none"), "");
});

test("formatRosterRow appends send targets in full (not truncated to width)", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "x/y", context: "", status: "idle", targets: "→main·3 coder·1 longtarget·2" },
		false,
		50, // >= fixed base width (45); targets then overflow it
	);
	assert.match(row, /→main·3 coder·1 longtarget·2$/);
	assert.ok(row.length > 50); // targets overflow width on purpose
});

test("formatRosterRow shows cursor, name, model, context, status", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "anthropic/claude-sonnet-4-5", context: "3k/200k · 2%", status: "thinking" },
		true,
		60,
	);
	assert.match(row, /▸/);
	assert.match(row, /echo/);
	assert.match(row, /thinking/);
	assert.match(row, /claude-sonnet-4/); // short id, provider prefix dropped
	assert.ok(row.length <= 60);
});

test("formatRosterRow truncates a long tool status to the column", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "x/y", context: "", status: "tool:some_very_long_tool" },
		false,
		80,
	);
	assert.match(row, /tool:some…/);
});

test("swarmStateLine: halted vs live with activity count", () => {
	assert.match(swarmStateLine(true, 3), /halted/);
	assert.match(swarmStateLine(true, 3), /unhalt/);
	assert.match(swarmStateLine(false, 2), /live · 2 working/);
	assert.match(swarmStateLine(false, 0), /live · idle/);
	assert.doesNotMatch(swarmStateLine(false, 0), /running/);
});

test("isBusy: idle/spawning/halted are not busy", () => {
	assert.equal(isBusy("idle"), false);
	assert.equal(isBusy("spawning"), false);
	assert.equal(isBusy("halted"), false);
	assert.equal(isBusy("thinking"), true);
	assert.equal(isBusy("writing"), true);
	assert.equal(isBusy("tool:bash"), true);
});

test("shortModel drops provider prefix and truncates", () => {
	assert.equal(shortModel("anthropic/opus"), "opus");
	assert.equal(shortModel("local-model"), "local-model");
	assert.equal(shortModel(undefined), "");
	assert.equal(shortModel("x/" + "a".repeat(40)).length, 16); // truncated to column width
});

test("mergeStreaming appends streaming msg, dedupes by identity", () => {
	const a = { role: "user" };
	const s = { role: "assistant" };
	assert.deepEqual(mergeStreaming([a], undefined), [a]);
	assert.deepEqual(mergeStreaming([a], s), [a, s]);
	assert.deepEqual(mergeStreaming([a, s], s), [a, s]); // already last -> no double
});

test("moveSelection clamps at both ends", () => {
	assert.equal(moveSelection(0, -1, 3), 0);
	assert.equal(moveSelection(0, 1, 3), 1);
	assert.equal(moveSelection(2, 1, 3), 2);
	assert.equal(moveSelection(0, 1, 0), 0); // empty
});

test("clampScroll keeps offset within [0, max]", () => {
	assert.equal(clampScroll(5, 100, 10), 5);
	assert.equal(clampScroll(-3, 100, 10), 0);
	assert.equal(clampScroll(95, 100, 10), 90); // max = total - viewport
	assert.equal(clampScroll(5, 8, 10), 0); // content shorter than viewport
});

test("chatboxToRoute maps selected agent + text, rejects empty", () => {
	assert.deepEqual(chatboxToRoute("echo", "ping"), { to: "echo", content: "ping" });
	assert.equal(chatboxToRoute("echo", "   "), null);
	assert.equal(chatboxToRoute(undefined, "ping"), null);
});

test("messageText extracts string or text parts", () => {
	assert.equal(messageText("hi"), "hi");
	assert.equal(
		messageText([
			{ type: "text", text: "a" },
			{ type: "image", data: "x" },
			{ type: "text", text: "b" },
		]),
		"ab",
	);
	assert.equal(messageText(undefined), "");
});

test("toolCalls extracts id/name/arguments from assistant content; findToolResult matches by id", () => {
	const m = {
		role: "assistant",
		content: [
			{ type: "text", text: "ok" },
			{ type: "toolCall", id: "c1", name: "send_message", arguments: { to: "main", content: "hi" } },
		],
	};
	assert.deepEqual(toolCalls(m), [{ id: "c1", name: "send_message", arguments: { to: "main", content: "hi" } }]);
	assert.deepEqual(toolCalls({ role: "user", content: "hi" }), []);

	const msgs = [
		{ role: "assistant", content: [] },
		{ role: "toolResult", toolCallId: "c1", content: "done" },
	];
	assert.equal(findToolResult(msgs, "c1")?.toolCallId, "c1");
	assert.equal(findToolResult(msgs, "nope"), undefined);
});
