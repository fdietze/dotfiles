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
