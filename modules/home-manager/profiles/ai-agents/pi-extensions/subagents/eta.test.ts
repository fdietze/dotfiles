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

test("formatEtaSuffix: future shows clock anchor + relative minutes", () => {
	const now = at(15, 0);
	assert.equal(formatEtaSuffix(at(15, 20), now), "ETA ~15:20 (in 20min)");
});

test("formatEtaSuffix: relative rolls over to hours+minutes at ≥60min", () => {
	const now = at(10, 0);
	assert.equal(formatEtaSuffix(at(11, 5), now), "ETA ~11:05 (in 1h 5min)");
});

test("formatEtaSuffix: overdue keeps the absolute anchor, drops the number", () => {
	const now = at(15, 30);
	assert.equal(formatEtaSuffix(at(15, 20), now), "ETA ~15:20 (overdue)");
});

test("formatEtaSuffix: exact boundary (now == etaTs) reads as overdue", () => {
	const t = at(15, 20);
	assert.equal(formatEtaSuffix(t, t), "ETA ~15:20 (overdue)");
});

test("formatEtaSuffix: zero-pads hours and minutes", () => {
	const now = at(9, 0);
	assert.equal(formatEtaSuffix(at(9, 5), now), "ETA ~09:05 (in 5min)");
});

test("formatEtaSuffix: minutes round to nearest whole", () => {
	const now = at(12, 0);
	// 90 seconds → rounds to 2min
	assert.equal(formatEtaSuffix(now + 90_000, now), "ETA ~12:01 (in 2min)");
});
