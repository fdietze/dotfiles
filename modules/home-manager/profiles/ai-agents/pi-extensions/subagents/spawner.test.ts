import { test } from "node:test";
import assert from "node:assert/strict";
import { Engine } from "./engine.ts";
import { createSpawner, type SessionLike } from "./spawner.ts";

class FakeSession implements SessionLike {
	delivered: string[] = [];
	aborted = 0;
	isStreaming = false;
	messages: unknown[] = [];
	lastDeliverAs: string | undefined;
	getContextUsage() {
		return { tokens: 0, contextWindow: 1000, percent: 0 };
	}
	private listeners: ((e: { type: string }) => void)[] = [];
	async sendUserMessage(text: string, options?: { deliverAs?: string }) {
		this.delivered.push(text);
		this.lastDeliverAs = options?.deliverAs;
	}
	async abort() {
		this.aborted++;
	}
	subscribe(l: (e: { type: string }) => void) {
		this.listeners.push(l);
		return () => {};
	}
	emit(type: string) {
		for (const l of this.listeners) l({ type });
	}
}

function withMain(engine: Engine, inbox: string[]) {
	engine.addAgent({
		name: "main",
		model: "test/m",
		handle: { deliver: async (t) => void inbox.push(t), abort: async () => {}, isStreaming: () => false },
		spawnedBy: "main",
		depth: 0,
		createdAt: 0,
		turns: 0,
		lastActivity: 0,
		streaming: false,
	});
}

test("smoke: spawn -> deliver -> reply -> budget abort -> halt", async () => {
	const engine = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 2 });
	const userInbox: string[] = [];
	withMain(engine, userInbox);

	const sessions = new Map<string, FakeSession>();
	const spawner = createSpawner({
		engine,
		resolveModel: (ref) => (ref === "bad/x" ? undefined : { provider: "test", id: "m", model: {} }),
		createSession: async (spec) => {
			const s = new FakeSession();
			sessions.set(spec.name, s);
			return s;
		},
	});

	// spawn echo
	const r = await spawner.spawnAgent({ name: "echo", systemPrompt: "reply to sender" }, "main");
	assert.equal(r.ok, true);
	assert.equal(engine.has("echo"), true);
	assert.equal(engine.get("echo")?.depth, 1);

	// main -> echo
	const rt = await engine.route("main", "echo", "ping");
	assert.equal(rt.ok, true);
	assert.deepEqual(sessions.get("echo")?.delivered, ["[message from main]: ping"]);
	// Inter-agent delivery uses steer (next-boundary), not followUp.
	assert.equal(sessions.get("echo")?.lastDeliverAs, "steer");

	// echo -> main (the reply path)
	await engine.route("echo", "main", "pong");
	assert.deepEqual(userInbox, ["[message from echo]: pong"]);

	// streaming state from session events
	sessions.get("echo")?.emit("agent_start");
	assert.equal(engine.get("echo")?.streaming, true);
	sessions.get("echo")?.emit("agent_end");
	assert.equal(engine.get("echo")?.streaming, false);

	// turn budget: 3rd turn_start exceeds budget(2) and aborts the session
	const echo = sessions.get("echo");
	echo?.emit("turn_start");
	echo?.emit("turn_start");
	echo?.emit("turn_start");
	assert.ok((echo?.aborted ?? 0) >= 1);

	// halt blocks routing
	engine.halt();
	const blocked = await engine.route("main", "echo", "again");
	assert.equal(blocked.ok, false);
});

test("deliver is fire-and-forget: does not await the target's turn", async () => {
	const engine = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 5 });
	withMain(engine, []);
	// sendUserMessage never resolves (simulates a long-running turn). spawnAgent with an
	// initial message must still resolve — otherwise the spawn_agent tool would hang.
	class BlockingSession extends FakeSession {
		async sendUserMessage() {
			return new Promise<void>(() => {});
		}
	}
	const spawner = createSpawner({
		engine,
		resolveModel: () => ({ provider: "t", id: "m", model: {} }),
		createSession: async () => new BlockingSession(),
	});
	const r = await spawner.spawnAgent({ name: "slow", systemPrompt: "r", message: "go" }, "main");
	assert.equal(r.ok, true);
	assert.match(r.msg, /sent initial message/);
});

test("deliver failure surfaces as an engine error event", async () => {
	const engine = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 5 });
	withMain(engine, []);
	class FailingSession extends FakeSession {
		async sendUserMessage(): Promise<void> {
			throw new Error("boom");
		}
	}
	const spawner = createSpawner({
		engine,
		resolveModel: () => ({ provider: "t", id: "m", model: {} }),
		createSession: async () => new FailingSession(),
	});
	await spawner.spawnAgent({ name: "bad", systemPrompt: "r", message: "go" }, "main");
	await new Promise((res) => setTimeout(res, 0)); // let the .catch microtask run
	const err = engine.events.find((e) => e.type === "error");
	assert.ok(err, "expected an error event");
	assert.equal((err as { name: string }).name, "bad");
	assert.match((err as { reason: string }).reason, /boom/);
});

test("spawn rejects unknown model", async () => {
	const engine = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 5 });
	const spawner = createSpawner({
		engine,
		resolveModel: (ref) => (ref ? { provider: "t", id: "m", model: {} } : undefined),
		createSession: async () => new FakeSession(),
	});
	// spawner 'ghost' not registered -> depth 0, no inherited model, no ref -> unknown model
	const r = await spawner.spawnAgent({ name: "x", systemPrompt: "r" }, "ghost");
	assert.equal(r.ok, false);
	assert.match(r.msg, /unknown model/i);
});

test("spawn rejects duplicate name", async () => {
	const engine = new Engine({ maxAgents: 8, maxSpawnDepth: 3, turnBudget: 5 });
	const userInbox: string[] = [];
	withMain(engine, userInbox);
	const spawner = createSpawner({
		engine,
		resolveModel: () => ({ provider: "t", id: "m", model: {} }),
		createSession: async () => new FakeSession(),
	});
	assert.equal((await spawner.spawnAgent({ name: "dup", systemPrompt: "r" }, "main")).ok, true);
	const second = await spawner.spawnAgent({ name: "dup", systemPrompt: "r" }, "main");
	assert.equal(second.ok, false);
	assert.match(second.msg, /already exists/i);
});

test("spawn enforces max depth via spawner depth", async () => {
	const engine = new Engine({ maxAgents: 8, maxSpawnDepth: 2, turnBudget: 5 });
	const userInbox: string[] = [];
	withMain(engine, userInbox);
	const spawner = createSpawner({
		engine,
		resolveModel: () => ({ provider: "t", id: "m", model: {} }),
		createSession: async () => new FakeSession(),
	});
	// main(0) -> a(1) -> b(2) ok; b spawning would be depth 3 > 2
	await spawner.spawnAgent({ name: "a", systemPrompt: "r" }, "main");
	await spawner.spawnAgent({ name: "b", systemPrompt: "r" }, "a");
	const tooDeep = await spawner.spawnAgent({ name: "c", systemPrompt: "r" }, "b");
	assert.equal(tooDeep.ok, false);
	assert.match(tooDeep.msg, /depth/i);
});
