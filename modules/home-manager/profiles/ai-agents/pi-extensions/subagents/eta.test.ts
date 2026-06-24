import { test } from "node:test";
import assert from "node:assert/strict";
import { formatEtaSuffix } from "./eta.ts";

// Build an absolute epoch ms for a given wall-clock H:M today, so the clock-time
// assertions are independent of the machine timezone (we read back via local getHours).
function at(h: number, m: number): number {
	const d = new Date();
	d.setHours(h, m, 0, 0);
	return d.getTime();
}

test("formatEtaSuffix: renders the absolute clock anchor, no relative hint", () => {
	assert.equal(formatEtaSuffix(at(15, 20)), "ETA ~15:20");
});

test("formatEtaSuffix: zero-pads hours and minutes", () => {
	assert.equal(formatEtaSuffix(at(9, 5)), "ETA ~09:05");
});
