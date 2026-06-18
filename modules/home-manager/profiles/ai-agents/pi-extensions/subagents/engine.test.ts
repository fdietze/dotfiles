import { test } from "node:test";
import assert from "node:assert/strict";
import { Engine, statusLabel, type AgentHandle } from "./engine.ts";

const fakeHandle = (): AgentHandle => ({
	deliver: async () => {},
	abort: async () => {},
	isStreaming: () => false,
});

const caps = { maxAgents: 2, maxSpawnDepth: 2, turnBudget: 5 };

function mainRecord() {
	return {
		name: "main",
		model: "anthropic/x",
		handle: fakeHandle(),
		spawnedBy: "main",
		depth: 0,
		createdAt: 0,
		turns: 0,
		lastActivity: 0,
		streaming: false,
	};
}

test("reportError clears streaming/activity so status does not stick mid-turn", () => {
	const e = new Engine(caps);
	e.addAgent({ ...mainRecord(), name: "w", depth: 1, streaming: true });
	e.setActivity("w", "thinking");
	assert.equal(statusLabel(e.get("w")!), "thinking");
	e.reportError("w", "boom");
	const rec = e.get("w")!;
	assert.equal(rec.streaming, false);
	assert.equal(rec.activity, undefined);
	assert.equal(statusLabel(rec), "idle");
	assert.equal(e.events.at(-1)?.type, "error");
});

test("addAgent registers and has/get work, emits spawn event", () => {
	const e = new Engine(caps);
	e.addAgent(mainRecord());
	assert.equal(e.has("main"), true);
	assert.equal(e.get("main")?.depth, 0);
	assert.equal(e.list().length, 1);
	assert.equal(e.events.at(-1)?.type, "spawn");
});

test("canSpawn rejects duplicate name", () => {
	const e = new Engine(caps);
	e.addAgent(mainRecord());
	const r = e.canSpawn("main", 0);
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /already exists|reserved/);
});

test("canSpawn rejects reserved name and invalid name", () => {
	const e = new Engine(caps);
	assert.equal(e.canSpawn("main", 0).ok, false); // reserved
	assert.equal(e.canSpawn("has space", 0).ok, false);
	assert.equal(e.canSpawn("", 0).ok, false);
});

test("canSpawn enforces maxAgents (excluding main)", () => {
	const e = new Engine(caps); // maxAgents = 2
	e.addAgent(mainRecord());
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
	e.addAgent({ ...mainRecord(), name: "b", depth: 1 });
	const r = e.canSpawn("c", 0);
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /max agents/i);
});

test("canSpawn enforces maxSpawnDepth", () => {
	const e = new Engine(caps); // maxSpawnDepth = 2
	const r = e.canSpawn("deep", 2); // spawnerDepth 2 -> child depth 3 > 2
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /depth/i);
});

test("route delivers prefixed message to existing agent when idle", async () => {
	const e = new Engine(caps);
	let delivered = "";
	const handle: AgentHandle = {
		deliver: async (t) => {
			delivered = t;
		},
		abort: async () => {},
		isStreaming: () => false,
	};
	e.addAgent({ ...mainRecord(), name: "coder", handle, depth: 1 });
	const r = await e.route("main", "coder", "fix the bug");
	assert.equal(r.ok, true);
	assert.equal(delivered, "[message from main]: fix the bug");
	assert.match((r as { status: string }).status, /woken|delivered/i);
	assert.equal(e.events.at(-1)?.type, "route");
});

test("route reports busy status when target is streaming", async () => {
	const e = new Engine(caps);
	const handle: AgentHandle = {
		deliver: async () => {},
		abort: async () => {},
		isStreaming: () => true,
	};
	e.addAgent({ ...mainRecord(), name: "busy", handle, depth: 1 });
	const r = await e.route("main", "busy", "hi");
	assert.equal(r.ok, true);
	assert.match((r as { status: string }).status, /queued|busy/i);
});

test("route fails for unknown agent", async () => {
	const e = new Engine(caps);
	const r = await e.route("main", "ghost", "hi");
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /unknown agent/i);
});

test("route is blocked while frozen", async () => {
	const e = new Engine(caps);
	e.addAgent({ ...mainRecord(), name: "coder", depth: 1 });
	e.halt();
	const r = await e.route("main", "coder", "hi");
	assert.equal(r.ok, false);
	assert.match((r as { reason: string }).reason, /halt/i);
	assert.equal(e.events.at(-1)?.type, "blocked");
});

test("recordTurnStart counts turns and aborts when budget exhausted", () => {
	const e = new Engine({ maxAgents: 5, maxSpawnDepth: 5, turnBudget: 2 });
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
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
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
	e.halt();
	const r = e.recordTurnStart("a");
	assert.equal(r.abort, true);
	assert.match(r.reason ?? "", /halt/i);
});

test("resume clears frozen and resets budget", () => {
	const e = new Engine({ maxAgents: 5, maxSpawnDepth: 5, turnBudget: 1 });
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
	e.recordTurnStart("a"); // uses budget
	e.halt();
	e.resume();
	assert.equal(e.isFrozen(), false);
	assert.equal(e.budget.used, 0);
	assert.equal(e.events.at(-1)?.type, "resume");
	assert.equal(e.recordTurnStart("a").abort, false);
});

test("freeze-by-blocking: budget-reaching turn completes, next is blocked, swarm freezes", () => {
	const e = new Engine({ maxAgents: 5, maxSpawnDepth: 5, turnBudget: 2 });
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
	assert.equal(e.recordTurnStart("a").abort, false); // used 1
	assert.equal(e.isFrozen(), false);
	assert.equal(e.recordTurnStart("a").abort, false); // used 2 == budget: completes, then freezes
	assert.equal(e.isFrozen(), true);
	assert.equal(e.events.at(-1)?.type, "halt");
	assert.equal((e.events.at(-1) as { reason?: string }).reason, "budget");
	const blocked = e.recordTurnStart("a"); // next turn blocked
	assert.equal(blocked.abort, true);
	assert.match(blocked.reason ?? "", /budget/i);
});

test("halt marks only streaming agents as halted; manual halt reason", () => {
	const e = new Engine(caps);
	e.addAgent({ ...mainRecord(), name: "busy", depth: 1, streaming: true });
	e.addAgent({ ...mainRecord(), name: "done", depth: 1, streaming: false });
	e.halt();
	assert.equal(e.get("busy")?.halted, true);
	assert.equal(e.get("done")?.halted, undefined);
	assert.equal((e.events.at(-1) as { type: string; reason?: string }).reason, "manual");
	// halted survives the natural agent_end of an allowed-to-complete turn.
	e.setStreaming("busy", false);
	assert.equal(e.get("busy")?.halted, true);
	assert.equal(statusLabel(e.get("busy")!), "halted");
	assert.equal(statusLabel(e.get("done")!), "idle");
});

test("resume clears halted flags", () => {
	const e = new Engine(caps);
	e.addAgent({ ...mainRecord(), name: "busy", depth: 1, streaming: true });
	e.halt();
	assert.equal(e.get("busy")?.halted, true);
	e.resume();
	assert.equal(e.get("busy")?.halted, false);
});

test("statusLabel: spawning and halted take precedence over streaming phase", () => {
	assert.equal(statusLabel({ pending: true, streaming: true, halted: true }), "spawning");
	assert.equal(statusLabel({ halted: true, streaming: true, activity: "tool", currentTool: "bash" }), "halted");
	assert.equal(statusLabel({ streaming: true, activity: "writing" }), "writing");
});

test("setStreaming updates record flag", () => {
	const e = new Engine(caps);
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
	e.setStreaming("a", true);
	assert.equal(e.get("a")?.streaming, true);
	e.setStreaming("a", false);
	assert.equal(e.get("a")?.streaming, false);
});

test("addAgent preserves optional view", () => {
	const e = new Engine(caps);
	const msgs: unknown[] = [{ role: "user", content: "hi" }];
	const view = {
		getMessages: () => msgs,
		getContextUsage: () => ({ tokens: 100, contextWindow: 200000, percent: 0.05 }),
		subscribe: () => () => {},
	};
	e.addAgent({ ...mainRecord(), name: "a", depth: 1, view });
	assert.equal(e.get("a")?.view?.getMessages().length, 1);
	assert.equal(e.get("a")?.view?.getContextUsage()?.contextWindow, 200000);
});

test("reserve blocks duplicate, counts toward cap; release frees a slot", () => {
	const e = new Engine({ maxAgents: 2, maxSpawnDepth: 3, turnBudget: 5 });
	assert.equal(e.reserve("a", "main").ok, true);
	assert.equal(e.reserve("a", "main").ok, false); // duplicate (R2)
	assert.equal(e.reserve("b", "main").ok, true);
	const capped = e.reserve("c", "main"); // a+b = max (R3)
	assert.equal(capped.ok, false);
	assert.match((capped as { reason: string }).reason, /max agents/);
	e.release("a");
	assert.equal(e.has("a"), false);
	assert.equal(e.reserve("c", "main").ok, true);
});

test("route to a pending agent buffers; attach flushes to the real handle (R1)", async () => {
	const e = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 5 });
	e.reserve("a", "main");
	const r = await e.route("main", "a", "ping");
	assert.equal(r.ok, true); // no longer "unknown agent"
	const delivered: string[] = [];
	e.attach("a", {
		model: "test/m",
		handle: { deliver: async (t) => void delivered.push(t), abort: async () => {}, isStreaming: () => false },
	});
	assert.deepEqual(delivered, ["[message from main]: ping"]); // buffer flushed
	assert.equal(e.get("a")?.pending, false);
	assert.equal(e.get("a")?.model, "test/m");
});

test("kill aborts the agent, runs dispose, removes it, and emits a kill event", () => {
	const e = new Engine(caps);
	e.addAgent(mainRecord());
	let aborted = 0;
	let disposed = 0;
	const handle: AgentHandle = { deliver: async () => {}, abort: async () => void aborted++, isStreaming: () => false };
	e.reserve("a", "main");
	e.attach("a", { model: "test/m", handle, dispose: () => void disposed++ });
	const r = e.kill("a");
	assert.equal(r.ok, true);
	assert.equal(aborted, 1);
	assert.equal(disposed, 1);
	assert.equal(e.has("a"), false);
	assert.equal(e.events.at(-1)?.type, "kill");
});

test("kill refuses 'main' and unknown agents", () => {
	const e = new Engine(caps);
	e.addAgent(mainRecord());
	const u = e.kill("main");
	assert.equal(u.ok, false);
	assert.match((u as { reason: string }).reason, /main/);
	const x = e.kill("ghost");
	assert.equal(x.ok, false);
	assert.match((x as { reason: string }).reason, /unknown/);
	assert.equal(e.has("main"), true);
});

test("killAll removes every agent except 'main' and returns their names", () => {
	const e = new Engine({ maxAgents: 5, maxSpawnDepth: 2, turnBudget: 5 });
	e.addAgent(mainRecord());
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
	e.addAgent({ ...mainRecord(), name: "b", depth: 1 });
	const killed = e.killAll();
	assert.deepEqual(killed.sort(), ["a", "b"]);
	assert.equal(e.has("main"), true);
	assert.equal(e.list().length, 1);
});

test("getMessageMatrix counts edges; multicast counts one per target", async () => {
	const e = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 50 });
	e.addAgent(mainRecord());
	e.addAgent({ ...mainRecord(), name: "a", depth: 1 });
	e.addAgent({ ...mainRecord(), name: "b", depth: 1 });
	await e.route("main", "a", "one");
	await e.route("main", "a", "two");
	await e.route("main", "b", "hi"); // multicast = caller loops route per target
	await e.route("a", "b", "back");
	const m = e.getMessageMatrix();
	assert.equal(m.main?.a, 2);
	assert.equal(m.main?.b, 1);
	assert.equal(m.a?.b, 1);
	// snapshot is a copy, not a live reference
	m.main.a = 999;
	assert.equal(e.getMessageMatrix().main.a, 2);
});

test("reserve records the spawn parent (child -> parent)", () => {
	const e = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 5 });
	e.addAgent(mainRecord());
	e.reserve("a", "main");
	e.attach("a", { model: "test/m", handle: fakeHandle() });
	e.reserve("b", "a");
	const tree = e.getSpawnTree();
	assert.equal(tree.a, "main");
	assert.equal(tree.b, "a");
	assert.equal(tree.main, undefined); // main is the root
});

test("re-spawning a killed name clears its incoming + outgoing edges and overwrites its parent", async () => {
	const e = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 50 });
	e.addAgent(mainRecord());
	e.reserve("a", "main");
	e.attach("a", { model: "test/m", handle: fakeHandle() });
	e.reserve("w", "a");
	e.attach("w", { model: "test/m", handle: fakeHandle() });
	await e.route("main", "w", "out-from-main"); // incoming edge main->w
	await e.route("w", "a", "out-from-w"); // outgoing edge w->a
	e.kill("w");
	// re-spawn 'w' under a different parent
	e.reserve("w", "main");
	const m = e.getMessageMatrix();
	assert.equal(m.main?.w, undefined); // incoming edge cleared
	assert.equal(m.w, undefined); // outgoing edges cleared
	assert.equal(e.getSpawnTree().w, "main"); // parent overwritten (was 'a')
});
