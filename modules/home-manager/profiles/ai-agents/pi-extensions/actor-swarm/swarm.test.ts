import { test } from "node:test";
import assert from "node:assert/strict";
import { Engine } from "./engine.ts";
import { createSpawner, type SessionLike } from "./swarm.ts";

class FakeSession implements SessionLike {
	delivered: string[] = [];
	aborted = 0;
	isStreaming = false;
	messages: unknown[] = [];
	getContextUsage() {
		return { tokens: 0, contextWindow: 1000, percent: 0 };
	}
	private listeners: ((e: { type: string }) => void)[] = [];
	async sendUserMessage(text: string) {
		this.delivered.push(text);
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

function withUser(engine: Engine, inbox: string[]) {
	engine.addActor({
		name: "user",
		model: "test/m",
		handle: { deliver: async (t) => void inbox.push(t), abort: async () => {}, isStreaming: () => false },
		spawnedBy: "user",
		depth: 0,
		createdAt: 0,
		turns: 0,
		lastActivity: 0,
		streaming: false,
	});
}

test("smoke: spawn -> deliver -> reply -> budget abort -> halt", async () => {
	const engine = new Engine({ maxActors: 8, maxSpawnDepth: 3, turnBudget: 2 });
	const userInbox: string[] = [];
	withUser(engine, userInbox);

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
	const r = await spawner.spawnActor({ name: "echo", systemPrompt: "reply to sender" }, "user");
	assert.equal(r.ok, true);
	assert.equal(engine.has("echo"), true);
	assert.equal(engine.get("echo")?.depth, 1);

	// user -> echo
	const rt = await engine.route("user", "echo", "ping");
	assert.equal(rt.ok, true);
	assert.deepEqual(sessions.get("echo")?.delivered, ["[message from user]: ping"]);

	// echo -> user (the reply path)
	await engine.route("echo", "user", "pong");
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
	const blocked = await engine.route("user", "echo", "again");
	assert.equal(blocked.ok, false);
});

test("spawn rejects unknown model", async () => {
	const engine = new Engine({ maxActors: 8, maxSpawnDepth: 3, turnBudget: 5 });
	const spawner = createSpawner({
		engine,
		resolveModel: (ref) => (ref ? { provider: "t", id: "m", model: {} } : undefined),
		createSession: async () => new FakeSession(),
	});
	// spawner 'ghost' not registered -> depth 0, no inherited model, no ref -> unknown model
	const r = await spawner.spawnActor({ name: "x", systemPrompt: "r" }, "ghost");
	assert.equal(r.ok, false);
	assert.match(r.msg, /unknown model/i);
});

test("spawn rejects duplicate name", async () => {
	const engine = new Engine({ maxActors: 8, maxSpawnDepth: 3, turnBudget: 5 });
	const userInbox: string[] = [];
	withUser(engine, userInbox);
	const spawner = createSpawner({
		engine,
		resolveModel: () => ({ provider: "t", id: "m", model: {} }),
		createSession: async () => new FakeSession(),
	});
	assert.equal((await spawner.spawnActor({ name: "dup", systemPrompt: "r" }, "user")).ok, true);
	const second = await spawner.spawnActor({ name: "dup", systemPrompt: "r" }, "user");
	assert.equal(second.ok, false);
	assert.match(second.msg, /already exists/i);
});

test("spawn enforces max depth via spawner depth", async () => {
	const engine = new Engine({ maxActors: 8, maxSpawnDepth: 2, turnBudget: 5 });
	const userInbox: string[] = [];
	withUser(engine, userInbox);
	const spawner = createSpawner({
		engine,
		resolveModel: () => ({ provider: "t", id: "m", model: {} }),
		createSession: async () => new FakeSession(),
	});
	// user(0) -> a(1) -> b(2) ok; b spawning would be depth 3 > 2
	await spawner.spawnActor({ name: "a", systemPrompt: "r" }, "user");
	await spawner.spawnActor({ name: "b", systemPrompt: "r" }, "a");
	const tooDeep = await spawner.spawnActor({ name: "c", systemPrompt: "r" }, "b");
	assert.equal(tooDeep.ok, false);
	assert.match(tooDeep.msg, /depth/i);
});
