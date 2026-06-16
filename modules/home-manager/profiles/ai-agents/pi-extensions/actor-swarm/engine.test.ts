import { test } from "node:test";
import assert from "node:assert/strict";
import { Engine, type ActorHandle } from "./engine.ts";

const fakeHandle = (): ActorHandle => ({
	deliver: async () => {},
	abort: async () => {},
	isStreaming: () => false,
});

const caps = { maxActors: 2, maxSpawnDepth: 2, turnBudget: 5 };

function userRecord() {
	return {
		name: "user",
		model: "anthropic/x",
		handle: fakeHandle(),
		spawnedBy: "user",
		depth: 0,
		createdAt: 0,
		turns: 0,
		lastActivity: 0,
		streaming: false,
	};
}

test("addActor registers and has/get work, emits spawn event", () => {
	const e = new Engine(caps);
	e.addActor(userRecord());
	assert.equal(e.has("user"), true);
	assert.equal(e.get("user")?.depth, 0);
	assert.equal(e.list().length, 1);
	assert.equal(e.events.at(-1)?.type, "spawn");
});

test("canSpawn rejects duplicate name", () => {
	const e = new Engine(caps);
	e.addActor(userRecord());
	const r = e.canSpawn("user", 0);
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /already exists|reserved/);
});

test("canSpawn rejects reserved name and invalid name", () => {
	const e = new Engine(caps);
	assert.equal(e.canSpawn("user", 0).ok, false); // reserved
	assert.equal(e.canSpawn("has space", 0).ok, false);
	assert.equal(e.canSpawn("", 0).ok, false);
});

test("canSpawn enforces maxActors (excluding user)", () => {
	const e = new Engine(caps); // maxActors = 2
	e.addActor(userRecord());
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.addActor({ ...userRecord(), name: "b", depth: 1 });
	const r = e.canSpawn("c", 0);
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /max actors/i);
});

test("canSpawn enforces maxSpawnDepth", () => {
	const e = new Engine(caps); // maxSpawnDepth = 2
	const r = e.canSpawn("deep", 2); // spawnerDepth 2 -> child depth 3 > 2
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /depth/i);
});

test("route delivers prefixed message to existing actor when idle", async () => {
	const e = new Engine(caps);
	let delivered = "";
	const handle: ActorHandle = {
		deliver: async (t) => {
			delivered = t;
		},
		abort: async () => {},
		isStreaming: () => false,
	};
	e.addActor({ ...userRecord(), name: "coder", handle, depth: 1 });
	const r = await e.route("user", "coder", "fix the bug");
	assert.equal(r.ok, true);
	assert.equal(delivered, "[message from user]: fix the bug");
	assert.match((r as { status: string }).status, /woken|delivered/i);
	assert.equal(e.events.at(-1)?.type, "route");
});

test("route reports busy status when target is streaming", async () => {
	const e = new Engine(caps);
	const handle: ActorHandle = {
		deliver: async () => {},
		abort: async () => {},
		isStreaming: () => true,
	};
	e.addActor({ ...userRecord(), name: "busy", handle, depth: 1 });
	const r = await e.route("user", "busy", "hi");
	assert.equal(r.ok, true);
	assert.match((r as { status: string }).status, /queued|busy/i);
});

test("route fails for unknown actor", async () => {
	const e = new Engine(caps);
	const r = await e.route("user", "ghost", "hi");
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /unknown actor/i);
});

test("route is blocked while frozen", async () => {
	const e = new Engine(caps);
	e.addActor({ ...userRecord(), name: "coder", depth: 1 });
	e.halt();
	const r = await e.route("user", "coder", "hi");
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /halt/i);
	assert.equal(e.events.at(-1)?.type, "blocked");
});

test("recordTurnStart counts turns and aborts when budget exhausted", () => {
	const e = new Engine({ maxActors: 5, maxSpawnDepth: 5, turnBudget: 2 });
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	assert.equal(e.recordTurnStart("a").abort, false);
	assert.equal(e.recordTurnStart("a").abort, false);
	const third = e.recordTurnStart("a");
	assert.equal(third.abort, true);
	assert.match(third.reason ?? "", /budget/i);
	assert.equal(e.get("a")?.turns, 2);
	assert.equal(e.budget.used, 2);
});

test("recordTurnStart aborts while frozen", () => {
	const e = new Engine(caps);
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.halt();
	const r = e.recordTurnStart("a");
	assert.equal(r.abort, true);
	assert.match(r.reason ?? "", /halt/i);
});

test("resume clears frozen and resets budget", () => {
	const e = new Engine({ maxActors: 5, maxSpawnDepth: 5, turnBudget: 1 });
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.recordTurnStart("a"); // uses budget
	e.halt();
	e.resume();
	assert.equal(e.isFrozen(), false);
	assert.equal(e.budget.used, 0);
	assert.equal(e.events.at(-1)?.type, "resume");
	assert.equal(e.recordTurnStart("a").abort, false);
});

test("setStreaming updates record flag", () => {
	const e = new Engine(caps);
	e.addActor({ ...userRecord(), name: "a", depth: 1 });
	e.setStreaming("a", true);
	assert.equal(e.get("a")?.streaming, true);
	e.setStreaming("a", false);
	assert.equal(e.get("a")?.streaming, false);
});

test("addActor preserves optional view", () => {
	const e = new Engine(caps);
	const msgs: unknown[] = [{ role: "user", content: "hi" }];
	const view = {
		getMessages: () => msgs,
		getContextUsage: () => ({ tokens: 100, contextWindow: 200000, percent: 0.05 }),
		subscribe: () => () => {},
	};
	e.addActor({ ...userRecord(), name: "a", depth: 1, view });
	assert.equal(e.get("a")?.view?.getMessages().length, 1);
	assert.equal(e.get("a")?.view?.getContextUsage()?.contextWindow, 200000);
});

test("reserve blocks duplicate, counts toward cap; release frees a slot", () => {
	const e = new Engine({ maxActors: 2, maxSpawnDepth: 3, turnBudget: 5 });
	assert.equal(e.reserve("a", "user").ok, true);
	assert.equal(e.reserve("a", "user").ok, false); // duplicate (R2)
	assert.equal(e.reserve("b", "user").ok, true);
	const capped = e.reserve("c", "user"); // a+b = max (R3)
	assert.equal(capped.ok, false);
	assert.match((capped as { reason: string }).reason, /max actors/);
	e.release("a");
	assert.equal(e.has("a"), false);
	assert.equal(e.reserve("c", "user").ok, true);
});

test("route to a pending actor buffers; attach flushes to the real handle (R1)", async () => {
	const e = new Engine({ maxActors: 8, maxSpawnDepth: 3, turnBudget: 5 });
	e.reserve("a", "user");
	const r = await e.route("user", "a", "ping");
	assert.equal(r.ok, true); // kein "unknown actor" mehr
	const delivered: string[] = [];
	e.attach("a", {
		model: "test/m",
		handle: { deliver: async (t) => void delivered.push(t), abort: async () => {}, isStreaming: () => false },
	});
	assert.deepEqual(delivered, ["[message from user]: ping"]); // Puffer geflusht
	assert.equal(e.get("a")?.pending, false);
	assert.equal(e.get("a")?.model, "test/m");
});
