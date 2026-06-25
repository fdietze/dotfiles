import { test } from "node:test";
import assert from "node:assert/strict";
import { formatResult, clampCursor, isNoteRow } from "./core.ts";

test("formatResult: selected + note uses original 1-based indices and joins both sides", () => {
	const r = formatResult(["A", "B", "C"], [false, true, true], "  hi  ");
	assert.deepEqual(r.selected, ["B", "C"]);
	assert.equal(r.note, "hi"); // trimmed
	assert.equal(r.content, "User selected: 2. B, 3. C | note: hi");
	assert.equal(r.isEmpty, false);
});

test("formatResult: selected only omits note side", () => {
	const r = formatResult(["A", "B"], [true, false], "   ");
	assert.deepEqual(r.selected, ["A"]);
	assert.equal(r.note, null);
	assert.equal(r.content, "User selected: 1. A");
	assert.equal(r.isEmpty, false);
});

test("formatResult: note only", () => {
	const r = formatResult(["A", "B"], [false, false], "ship it");
	assert.deepEqual(r.selected, []);
	assert.equal(r.note, "ship it");
	assert.equal(r.content, "User note: ship it");
	assert.equal(r.isEmpty, false);
});

test("formatResult: empty submit is valid, not cancel", () => {
	const r = formatResult(["A"], [false], "");
	assert.equal(r.content, "User submitted empty answer (no options, no note)");
	assert.equal(r.isEmpty, true);
	assert.equal(r.note, null);
});

test("formatResult: works with zero options (note-only path)", () => {
	const r = formatResult([], [], "just a note");
	assert.equal(r.content, "User note: just a note");
	assert.deepEqual(r.selected, []);
});

test("clampCursor: valid rows are 0..optionCount inclusive (note row = optionCount)", () => {
	assert.equal(clampCursor(-1, 3), 0);
	assert.equal(clampCursor(5, 3), 3); // note row
	assert.equal(clampCursor(2, 3), 2);
});

test("isNoteRow: true only at index optionCount", () => {
	assert.equal(isNoteRow(3, 3), true);
	assert.equal(isNoteRow(2, 3), false);
	assert.equal(isNoteRow(0, 0), true); // no options: row 0 is the note row
});
