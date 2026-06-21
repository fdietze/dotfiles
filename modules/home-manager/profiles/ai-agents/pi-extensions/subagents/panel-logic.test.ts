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
	statusTone,
	toolPreviewParts,
	swarmStateLine,
	sendTargets,
	formatSendTargets,
	formatHistory,
} from "./panel-logic.ts";

const histMsgs = [
	{ role: "user", content: "start task" },
	{
		role: "assistant",
		content: [
			{ type: "thinking", thinking: "secret reasoning" },
			{ type: "text", text: "on it" },
			{ type: "toolCall", id: "t1", name: "send_message", arguments: { to: "main", content: "hi" } },
		],
	},
	{ role: "toolResult", toolCallId: "t1", content: [{ type: "text", text: "sent to main" }] },
	{ role: "assistant", content: [{ type: "text", text: "done" }] },
];

test("formatHistory: default offset 0 shows beginning + system prompt + header total", () => {
	const out = formatHistory({ name: "comic", systemPrompt: "be funny", messages: histMsgs, limit: 2 });
	assert.match(out, /agent comic · 4 messages · showing \[0, 2\)/);
	assert.match(out, /── system ──\nbe funny/);
	assert.match(out, /#0 user: start task/);
	assert.doesNotMatch(out, /#3/); // limited to 2
});

test("formatHistory: negative offset shows the tail, no system prompt", () => {
	const out = formatHistory({ name: "comic", systemPrompt: "be funny", messages: histMsgs, offset: -1 });
	assert.match(out, /showing \[3, 4\)/);
	assert.match(out, /#3 assistant: done/);
	assert.doesNotMatch(out, /── system ──/); // window does not cover index 0
});

test("formatHistory: thinking shown/hidden per flag; tool calls + results rendered", () => {
	const shown = formatHistory({ name: "a", messages: histMsgs, offset: 1, limit: 2 });
	assert.match(shown, /assistant·thinking: secret reasoning/);
	assert.match(shown, /⚙ send_message\(/);
	assert.match(shown, /⚙→ sent to main/);
	const hidden = formatHistory({ name: "a", messages: histMsgs, offset: 1, limit: 2, hideThinking: true });
	assert.doesNotMatch(hidden, /secret reasoning/);
	assert.match(hidden, /assistant: on it/);
});

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
	);
	assert.match(row, /→main·3 coder·1 longtarget·2$/); // targets always appended in full (renderer bounds width)
});

test("formatRosterRow shows custom status before the system status", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "x/y", context: "", status: "idle", customStatus: "parsing files" },
		false,
	);
	assert.match(row, /parsing files · idle/);
});

test("formatRosterRow: custom status does not make an idle agent read as busy", () => {
	// styleStatus receives tone "idle" for idle, even with a custom status set.
	const row = formatRosterRow(
		{ name: "echo", model: "x/y", context: "", status: "idle", customStatus: "waiting" },
		false,
		(label, tone) => (tone === "busy" ? `BUSY[${label}]` : label),
	);
	assert.doesNotMatch(row, /BUSY/);
});

test("formatRosterRow truncates a long combined status to the column", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "x/y", context: "", status: "idle", customStatus: "a much longer status than fits the column" },
		false,
	);
	assert.match(row, /a much longer status than fits the …/); // truncated at STATUS_COL (36) with ellipsis
});

test("formatRosterRow shows cursor, name, model, context, status", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "anthropic/claude-sonnet-4-5", context: "3k/200k · 2%", status: "thinking" },
		true,
	);
	assert.match(row, /▸/);
	assert.match(row, /echo/);
	assert.match(row, /thinking/);
	assert.match(row, /claude-sonnet-4/); // short id, provider prefix dropped
});

test("formatRosterRow truncates a long tool status to the column", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "x/y", context: "", status: "tool:some_very_long_tool_name_that_overflows" },
		false,
	);
	assert.match(row, /tool:some_very_long_tool_name_that_…/); // truncated at STATUS_COL (36)
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

test("toolPreviewParts: systemPrompt/message/content are always blocks, others inline", () => {
	const { scalars, blocks } = toolPreviewParts({
		name: "w1",
		model: "x/y",
		offset: -10,
		to: ["a", "b"],
		systemPrompt: "you are w1", // short, still a block (field-based, no length logic)
		message: "go",
	});
	assert.deepEqual(scalars, ["name=w1", "model=x/y", "offset=-10", 'to=["a","b"]']);
	assert.deepEqual(blocks, [
		{ key: "systemPrompt", value: "you are w1" },
		{ key: "message", value: "go" },
	]);
});

test("toolPreviewParts: a long non-payload field stays inline (no length heuristic)", () => {
	const longStatus = "x".repeat(80);
	const { scalars, blocks } = toolPreviewParts({ status: longStatus });
	assert.deepEqual(scalars, [`status=${longStatus}`]);
	assert.equal(blocks.length, 0);
});

test("toolPreviewParts: no args -> empty", () => {
	const { scalars, blocks } = toolPreviewParts({});
	assert.equal(scalars.length, 0);
	assert.equal(blocks.length, 0);
});

test("statusTone: error is its own tone, truncated dims like idle, work is busy", () => {
	assert.equal(statusTone("error"), "error");
	assert.equal(statusTone("truncated"), "idle");
	assert.equal(statusTone("idle"), "idle");
	assert.equal(statusTone("halted"), "idle");
	assert.equal(statusTone("thinking"), "busy");
	assert.equal(statusTone("tool:bash"), "busy");
});

test("formatRosterRow passes the error tone to the styler", () => {
	const row = formatRosterRow(
		{ name: "echo", model: "x/y", context: "", status: "error", customStatus: "drafting joke" },
		// custom status now leads, system status trails: "drafting joke · error"
		false,
		(label, tone) => `[${tone}]${label}`,
	);
	assert.match(row, /\[error\]/);
	assert.match(row, /drafting joke · error/);
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
