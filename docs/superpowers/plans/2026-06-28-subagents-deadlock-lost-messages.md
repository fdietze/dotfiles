# subagents Deadlock Lost Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the subagent deadlock caused when a budget-reaching turn halts but its outgoing `send_message` tool gets blocked by the frozen route.

**Architecture:** Defer message delivery on frozen routes by buffering messages in `AgentRecord.frozenInbox` and flushing them via `handle.deliver` on `resume()`.

**Tech Stack:** TypeScript, Bun (for testing, matching existing `node_modules` structure).

## Global Constraints

- Never break the `reserve`/`attach` background buffering behavior.
- Strictly adhere to TypeScript and ensure all code compiles under existing workspace settings.
- Bump the `ENGINE_KEY` to force pi to load the new Engine shape and avoid runtime crashes on hot reloading.

---

### Task 1: Update Types and Engine Key

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.ts`
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/index.ts`

**Interfaces:**
- Consumes: Existing `AgentRecord` type.
- Produces: `AgentRecord` with `frozenInbox?: string[]`, and bumped `ENGINE_KEY = "__subagentsEngine_v9"`.

- [ ] **Step 1: Add frozenInbox to AgentRecord**

Modify `engine.ts` to add the new in-memory optional array:
```typescript
export interface AgentRecord {
	// ... (keep all existing fields)
	/** Messages buffered while the swarm is frozen (manual /halt or turn-budget). Flushed on resume. */
	frozenInbox?: string[];
}
```

- [ ] **Step 2: Bump ENGINE_KEY in index.ts**

Modify `index.ts` to bump the Engine key from `__subagentsEngine_v8` to `__subagentsEngine_v9`:
```typescript
const ENGINE_KEY = "__subagentsEngine_v9";
```

- [ ] **Step 3: Run existing tests to verify type check passes**

Run: `bun test modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts`
Expected: PASS (no type errors, no broken behavior yet)

- [ ] **Step 4: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.ts modules/home-manager/profiles/ai-agents/pi-extensions/subagents/index.ts
git commit -m "feat(subagents): add frozenInbox to AgentRecord and bump ENGINE_KEY"
```

---

### Task 2: Modify Route to Buffer When Frozen

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.ts`
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts`

**Interfaces:**
- Consumes: `this.frozen` and `target.frozenInbox`.
- Produces: `route()` returning `{ ok: true; status: "buffered (halted)" }` when `this.frozen === true`.

- [ ] **Step 1: Write the failing test**

In `engine.test.ts`, replace the existing block check `test("route is blocked while frozen", ...)` with a test verifying that route instead buffers the message when frozen:
```typescript
test("route buffers while frozen", async () => {
	const e = new Engine(CAPS);
	let delivered = "";
	const handle: AgentHandle = {
		deliver: async (t) => {
			delivered = t;
		},
		abort: async () => {},
		isStreaming: () => false,
	};
	e.addAgent({
		name: "coder",
		model: "openai/gpt-4o",
		handle,
		spawnedBy: "main",
		depth: 1,
		createdAt: Date.now(),
		turns: 0,
		lastActivity: Date.now(),
		streaming: false,
	});

	e.halt();
	const r = await e.route("main", "coder", "hi");

	assert.equal(r.ok, true);
	assert.equal((r as { status: string }).status, "buffered (halted)");
	assert.equal(delivered, ""); // Should not deliver
	assert.deepEqual(e.get("coder")?.frozenInbox, ["[message from main]: hi"]);
	assert.equal(e.events.at(-1)?.type, "route"); // Verify edge count and route event still fired
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts`
Expected: FAIL (either type or assertions mismatch on `route is blocked while frozen` expecting block)

- [ ] **Step 3: Modify route() in engine.ts**

Replace the current frozen branch check in `route()`:
```typescript
		if (this.frozen) {
			const reason = "agents halted (use /unhalt)";
			this.emit({ type: "blocked", reason, ts: Date.now() });
			return { ok: false, reason };
		}
```
with:
```typescript
		if (this.frozen) {
			(target.frozenInbox ??= []).push(text);
			target.lastActivity = Date.now();
			let targets = this.messageEdges.get(from);
			if (!targets) {
				targets = new Map<string, number>();
				this.messageEdges.set(from, targets);
			}
			targets.set(to, (targets.get(to) ?? 0) + 1);
			const preview = content.length > 60 ? `${content.slice(0, 60)}...` : content;
			this.emit({ type: "route", from, to, preview, ts: Date.now() });
			return { ok: true, status: "buffered (halted)" };
		}
```

- [ ] **Step 4: Run tests to verify passing**

Run: `bun test modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.ts modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts
git commit -m "feat(subagents): buffer messages in frozenInbox on route() when frozen"
```

---

### Task 3: Modify Resume to Flush Buffers

**Files:**
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.ts`
- Modify: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts`

**Interfaces:**
- Consumes: `resume()` method in Engine.
- Produces: Cleared `frozenInbox` arrays and delivered buffered messages upon calling `resume()`.

- [ ] **Step 1: Write failing tests**

In `engine.test.ts`, write tests to verify that `resume()` flushes `frozenInbox` and that an idle agent receives a buffered message on resume:
```typescript
test("resume flushes buffered inbox in order", async () => {
	const e = new Engine(CAPS);
	const delivered: string[] = [];
	const handle: AgentHandle = {
		deliver: async (t) => {
			delivered.push(t);
		},
		abort: async () => {},
		isStreaming: () => false,
	};
	e.addAgent({
		name: "coder",
		model: "openai/gpt-4o",
		handle,
		spawnedBy: "main",
		depth: 1,
		createdAt: Date.now(),
		turns: 0,
		lastActivity: Date.now(),
		streaming: false,
	});

	e.halt();
	await e.route("main", "coder", "ping 1");
	await e.route("main", "coder", "ping 2");

	assert.deepEqual(delivered, []); // Buffered

	e.resume();

	assert.deepEqual(delivered, ["[message from main]: ping 1", "[message from main]: ping 2"]);
	assert.equal(e.get("coder")?.frozenInbox, undefined);
});

test("deadlock: budget-reaching turn's route buffers, idle recipient receives on resume", async () => {
	const e = new Engine({ ...CAPS, turnBudget: 1 });
	const delivered: string[] = [];
	
	e.addAgent({
		name: "explore",
		model: "openai/gpt-4o",
		handle: { deliver: async () => {}, abort: async () => {}, isStreaming: () => false },
		spawnedBy: "main",
		depth: 1,
		createdAt: Date.now(),
		turns: 0,
		lastActivity: Date.now(),
		streaming: false,
	});
	
	e.addAgent({
		name: "exploit",
		model: "openai/gpt-4o",
		handle: { deliver: async (t) => { delivered.push(t); }, abort: async () => {}, isStreaming: () => false },
		spawnedBy: "main",
		depth: 1,
		createdAt: Date.now(),
		turns: 0,
		lastActivity: Date.now(),
		streaming: false,
	});

	// explore starts its turn - reaches budget limit (1/1)
	const startResult = e.recordTurnStart("explore");
	assert.equal(startResult.abort, false); // allowed to complete
	assert.equal(e.isFrozen(), true); // Swarm is now frozen

	// explore sends message to exploit during its budget-reaching turn
	const routeResult = await e.route("explore", "exploit", "do the work");
	assert.equal(routeResult.ok, true);
	assert.equal((routeResult as { status: string }).status, "buffered (halted)");
	assert.deepEqual(delivered, []); // exploit didn't receive it yet

	// User resumes the swarm
	e.resume();

	// exploit gets the message flushed
	assert.deepEqual(delivered, ["[message from explore]: do the work"]);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bun test modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts`
Expected: FAIL (assertion on `delivered` fails because `resume()` doesn't flush anything yet)

- [ ] **Step 3: Implement flush logic in resume()**

In `engine.ts`, update `resume()`:
```typescript
	resume(): void {
		this.frozen = false;
		this.frozenReason = undefined;
		this.turnsUsed = 0;
		for (const rec of this.agents.values()) rec.halted = false;

		// Flush frozen inboxes
		for (const rec of this.agents.values()) {
			const inbox = rec.frozenInbox;
			if (inbox && inbox.length > 0) {
				rec.frozenInbox = undefined;
				for (const t of inbox) {
					void rec.handle.deliver(t);
				}
			}
		}

		this.emit({ type: "resume", ts: Date.now() });
	}
```

- [ ] **Step 4: Run tests to verify passing**

Run: `bun test modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.ts modules/home-manager/profiles/ai-agents/pi-extensions/subagents/engine.test.ts
git commit -m "feat(subagents): flush frozenInbox buffers on resume()"
```
