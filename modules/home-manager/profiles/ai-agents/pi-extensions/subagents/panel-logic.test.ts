import { test } from "node:test";
import assert from "node:assert/strict";
import {
	formatContext,
	formatRoster,
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

test("formatContext renders tokens/window only (no percentage), dash when unknown", () => {
	assert.match(formatContext({ tokens: 12000, contextWindow: 200000, percent: 6 }), /12k\/200k/);
	assert.doesNotMatch(formatContext({ tokens: 12000, contextWindow: 200000, percent: 6 }), /%/);
	assert.equal(formatContext({ tokens: null, contextWindow: 200000, percent: null }), "—");
	assert.equal(formatContext(undefined), "—");
	assert.doesNotMatch(formatContext({ tokens: 15000, contextWindow: 200000, percent: 7 }), /·/);
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

test("formatSendTargets: ➜name[count], count omitted for a single message; '' when none", () => {
	const matrix = { a: { main: 3, coder: 1 } };
	assert.equal(formatSendTargets(matrix, "a"), "➜main[3] ➜coder");
	assert.equal(formatSendTargets(matrix, "none"), "");
});

// ── formatRoster: responsive aligned single-line table ──
const re = (over: Record<string, unknown> = {}) => ({ name: "a", model: "x/y", context: "", status: "idle", ...over });

test("formatRoster: aligns the status column across rows (shared name-column width)", () => {
	const rows = formatRoster([re({ name: "ab", status: "idle" }), re({ name: "abcdef", status: "thinking" })], 200);
	assert.equal(rows[0].indexOf("idle"), rows[1].indexOf("thinking")); // same x → aligned
});

test("formatRoster: name middle-ellipsis keeps the distinguishing tail (shared-prefix names stay distinct)", () => {
	const rows = formatRoster(
		[re({ name: "risk-R-UniformApp-pipeline-5" }), re({ name: "risk-R-UniformApp-pipeline-7" })],
		200,
	);
	assert.notEqual(rows[0], rows[1]); // tails preserved → distinguishable
	assert.match(rows[0], /…/); // middle ellipsis applied (name > cap 24)
	assert.match(rows[0], /5\b/);
	assert.match(rows[1], /7\b/);
});

test("formatRoster: custom status leads, system status trails, both present", () => {
	const row = formatRoster([re({ customStatus: "parsing files", status: "idle" })], 200)[0];
	assert.match(row, /parsing files.*idle/);
});

test("formatRoster: ETA renders in its own column; column absent when no agent has one", () => {
	const eta = new Date();
	eta.setHours(15, 20, 0, 0);
	assert.match(formatRoster([re({ etaTs: eta.getTime() })], 200)[0], /ETA ~15:20/);
	assert.doesNotMatch(formatRoster([re({})], 200)[0], /ETA/);
});

test("formatRoster: ETA column padded blank for agents without one when another has it", () => {
	const eta = new Date();
	eta.setHours(15, 20, 0, 0);
	const rows = formatRoster([re({ name: "a", etaTs: eta.getTime() }), re({ name: "b" })], 200);
	assert.match(rows[0], /ETA ~15:20/);
	assert.doesNotMatch(rows[1], /ETA/);
});

test("formatRoster: collapse order under narrowing width is model → targets → context → custom", () => {
	const e = re({
		name: "agent",
		customStatus: "running tests",
		status: "tool:bash",
		context: "15k/200k (7%)",
		model: "anthropic/opus",
		targets: "➜main[3]",
	});
	const at = (w: number) => formatRoster([e], w)[0];
	// full row (computed width 59): everything present
	assert.match(at(59), /opus/);
	assert.match(at(59), /➜main\[3\]/);
	// model dropped first
	assert.doesNotMatch(at(55), /opus/);
	assert.match(at(55), /➜main\[3\]/);
	// then targets
	assert.doesNotMatch(at(50), /➜main/);
	assert.match(at(50), /15k\/200k/);
	// then context
	assert.doesNotMatch(at(40), /15k\/200k/);
	assert.match(at(40), /running tests/);
	// then custom — only protected (name + system status) survive
	assert.doesNotMatch(at(25), /running tests/);
	assert.match(at(25), /tool:bash/);
	assert.match(at(25), /agent/);
});

test("formatRoster: custom status capped at 32 with a trailing ellipsis", () => {
	const row = formatRoster([re({ customStatus: "x".repeat(50), status: "idle" })], 200)[0];
	assert.match(row, /x{31}…/); // 31 chars + ellipsis = 32
	assert.doesNotMatch(row, /x{33}/);
});

test("formatRoster: ▸ cursor on the selected row only", () => {
	const rows = formatRoster([re({ name: "a" }), re({ name: "b" })], 200, { selectedIndex: 1 });
	assert.match(rows[1], /^▸ /);
	assert.match(rows[0], /^ {2}/); // space cursor + gap → two leading spaces
});

test("formatRoster: tone keys off the system status — idle stays idle despite a custom status", () => {
	const row = formatRoster([re({ status: "idle", customStatus: "waiting" })], 200, {
		styleStatus: (l, tone) => (tone === "busy" ? `BUSY[${l}]` : l),
	})[0];
	assert.doesNotMatch(row, /BUSY/);
});

test("formatRoster: passes the error tone to the styler", () => {
	const row = formatRoster([re({ status: "error", customStatus: "drafting joke" })], 200, {
		styleStatus: (l, tone) => `[${tone}]${l}`,
	})[0];
	assert.match(row, /\[error\]/);
	assert.match(row, /drafting joke/);
});

test("formatRoster: model id shown in full (provider prefix dropped, no hard cap)", () => {
	const row = formatRoster([re({ model: "anthropic/claude-sonnet-4-5", status: "thinking" })], 200)[0];
	assert.match(row, /claude-sonnet-4-5/);
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

test("shortModel drops the provider prefix, no truncation (model column sizes itself)", () => {
	assert.equal(shortModel("anthropic/opus"), "opus");
	assert.equal(shortModel("local-model"), "local-model");
	assert.equal(shortModel(undefined), "");
	assert.equal(shortModel("x/" + "a".repeat(40)), "a".repeat(40));
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
