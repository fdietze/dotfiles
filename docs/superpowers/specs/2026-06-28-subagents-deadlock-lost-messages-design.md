# Spec: Subagents Deadlock & Lost Messages Resolution

## Context & Problem Statement

In the pi multi-agent subagent swarm, deadlocks can occur due to "lost messages" when the global turn budget is exhausted. 

### The Mechanism of the Deadlock

1. **Admitting the Turn:** When an agent (e.g. `explore`) starts a turn, `recordTurnStart` is called. It increments `turnsUsed`.
2. **Synchronous Halt:** If `turnsUsed` reaches the `turnBudget`, `recordTurnStart` immediately calls `halt("budget")`, setting `frozen = true` in the engine.
3. **Turn Allowed to Complete:** `recordTurnStart` returns `abort: false` so that the current (budget-reaching) turn can complete its LLM inference and reasoning loop cleanly, rather than being forcefully killed mid-thought.
4. **Outbound Communication Gated:** The agent completes its thinking, composes its output, and invokes the `send_message` tool to transmit the payload to another agent (e.g. `exploit`).
5. **Silently Rejected Route:** The `send_message` tool invokes `engine.route(from, to, content)`. However, `engine.route` checks `this.frozen` as its very first guard. Since `frozen` was set to `true` during `turn_start` (step 2), the message is rejected with `{ ok: false, reason: "agents halted (use /unhalt)" }`.
6. **Recipient Idle/Stalled:** `exploit` never receives the message. On `/unhalt` or `resume_agents()`, only agents marked `halted` (who were mid-stream when the freeze occurred) are sent the `RESUME_NUDGE`. Since `exploit` was idle-waiting for the message, it is NOT marked `halted`, receives no nudge, and sits idle forever. Both agents are now idle; the conversation is deadlocked.

This is a classic violation of **Separation of Concerns (SoC)**: the `frozen` flag conflates "block new turn execution" with "block message delivery."

---

## Proposed Solution: Approach A (Buffer-on-Frozen, Flush-on-Resume)

Instead of dropping or rejecting messages when the swarm is frozen, the system will **defer delivery** by buffering them in the target agent's record. When the swarm is resumed, all buffered messages will be flushed in order.

### Design Principles Applied

- **Separation of Concerns (SoC):** Decouple turn gating from communication routing. `frozen` blocks subsequent execution blocks, while messaging safely buffers.
- **Keep It Simple, Stupid (KISS):** Reuses the existing buffer/flush pattern built into the engine for the `reserve`/`attach` lifecycle of spawned-but-not-yet-ready sessions.
- **Correctness by Construction:** By changing the routing interface to always succeed when the target exists (even if deferred), the caller (`send_message`) receives a successful response, allowing the current turn to complete gracefully without breaking conversation chains.

---

## Technical Details

### 1. Data Structure Updates (`engine.ts`)

Introduce a new property `frozenInbox` to `AgentRecord` to queue messages routed while frozen.

```typescript
export interface AgentRecord {
	// ... existing fields ...
	/** Messages buffered while the swarm is frozen (manual /halt or turn-budget). Flushed on resume. */
	frozenInbox?: string[];
}
```

Since the engine singleton survives `/reload` and keeps its methods but its shape can change, we **must** bump `ENGINE_KEY` in `index.ts`:
```typescript
const ENGINE_KEY = "__subagentsEngine_v9"; // Bumped from v8
```

### 2. Message Routing Modification (`engine.ts`)

Modify `route()` to buffer messages when the swarm is frozen rather than rejecting them:

```typescript
async route(
	from: string,
	to: string,
	content: string,
): Promise<{ ok: true; status: string } | { ok: false; reason: string }> {
	const target = this.agents.get(to);
	if (!target) return { ok: false, reason: `unknown agent '${to}'` };

	const text = `[message from ${from}]: ${content}`;

	if (this.frozen) {
		(target.frozenInbox ??= []).push(text);
		target.lastActivity = Date.now();
		
		// Still count the message edge for the relationship graph
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

	// Normal path (unchanged) ...
	const wasStreaming = target.handle.isStreaming();
	await target.handle.deliver(text);
	// ...
}
```

### 3. Resuming the Swarm (`engine.ts` & `index.ts`)

In `engine.ts`, `resume()` must clear the `frozen` state *before* flushing the buffers to ensure that delivered messages can start their turns cleanly without being immediately blocked.

```typescript
resume(): void {
	this.frozen = false;
	this.frozenReason = undefined;
	this.turnsUsed = 0;

	// Clear halted states
	for (const rec of this.agents.values()) {
		rec.halted = false;
	}

	// Flush frozen inboxes
	for (const rec of this.agents.values()) {
		const inbox = rec.frozenInbox;
		if (inbox && inbox.length > 0) {
			rec.frozenInbox = undefined;
			for (const t of inbox) {
				void rec.handle.deliver(t); // Delivers live since frozen = false
			}
		}
	}

	this.emit({ type: "resume", ts: Date.now() });
}
```

In `index.ts`, `resumeAgents()` remains unchanged:
```typescript
const resumeAgents = (): number => {
	const halted = engine
		.list()
		.filter((a) => a.name !== "main" && a.halted)
		.map((a) => a.name);

	engine.resume(); // Clears frozen, resets budget, flushes frozenInboxes.

	for (const name of halted) void engine.route("main", name, RESUME_NUDGE);
	return halted.length;
};
```

This guarantees:
1. Mid-stream `halted` agents get their `RESUME_NUDGE`.
2. Idle-waiting agents (like `exploit`) get their buffered messages delivered, waking them up naturally.
3. Both sets of agents resume cleanly without missing any messages or needing complex state tracing.

### 4. Known Limitations

- **In-memory queue:** `frozenInbox` is an in-memory-only array. If the user stops/restarts the entire pi agent process during a halt, any buffered in-flight messages are lost (they are never written to the JSONL sessions). This is acceptable under **YAGNI** because a pi restart during a halt is extremely rare, and resolving it would add significant complexity (synchronizing message queues to `roster.json` on disk).

---

## Test & Verification Plan

### Automated Tests (`engine.test.ts`)

1. **Replace block check:** Replace `test("route is blocked while frozen")` with `test("route buffers while frozen")`. Verify that calling `route()` while frozen returns `ok: true`, buffers the message in `frozenInbox`, increments message edges, emits a `route` event, and does *not* call `handle.deliver`.
2. **Buffer flushing on resume:** Add `test("resume flushes buffered inbox in order")`. Verify that calling `resume()` flushes `frozenInbox` messages via `handle.deliver` to the target in chronological order, and clears the `frozenInbox` array.
3. **Deadlock scenario regression test:** Add `test("deadlock: budget-reaching turn's route buffers, idle recipient receives on resume")`. Mimic the explore/exploit deadlock:
   - Hit the turn budget.
   - Send message to an idle recipient.
   - Verify it's buffered, target remains idle.
   - Resume.
   - Verify recipient's deliver handler receives the message.
