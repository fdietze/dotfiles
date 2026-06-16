import { test } from "node:test";
import assert from "node:assert/strict";
import {
	formatContext,
	formatRosterRow,
	moveSelection,
	clampScroll,
	chatboxToRoute,
	messageText,
	toolCallLabels,
} from "./panel-logic.ts";

test("formatContext renders tokens/window/percent (percent is already 0-100), dash when unknown", () => {
	// pi's ContextUsage.percent is already a percentage (footer.js uses it directly).
	assert.match(formatContext({ tokens: 12000, contextWindow: 200000, percent: 6 }), /12k\/200k.*6%/);
	assert.match(formatContext({ tokens: 124000, contextWindow: 200000, percent: 62 }), /62%/);
	assert.equal(formatContext({ tokens: null, contextWindow: 200000, percent: null }), "—");
	assert.equal(formatContext(undefined), "—");
});

test("formatRosterRow shows cursor, name, context, status", () => {
	const row = formatRosterRow({ name: "echo", context: "3k/200k · 2%", active: true }, true, 40);
	assert.match(row, /▸/);
	assert.match(row, /echo/);
	assert.match(row, /active/);
	assert.ok(row.length <= 40);
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

test("chatboxToRoute maps selected actor + text, rejects empty", () => {
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

test("toolCallLabels extracts toolCall names from assistant content", () => {
	const m = {
		role: "assistant",
		content: [
			{ type: "text", text: "ok" },
			{ type: "toolCall", name: "send_message", arguments: {} },
		],
	};
	assert.deepEqual(toolCallLabels(m), ["⚙ send_message"]);
	assert.deepEqual(toolCallLabels({ role: "user", content: "hi" }), []);
});
