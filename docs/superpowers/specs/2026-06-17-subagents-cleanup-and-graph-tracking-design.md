# Subagents extension: cleanup, full toolset, and graph tracking

Date: 2026-06-17
Touches: `modules/home-manager/profiles/ai-agents/pi-extensions/subagents/`
Builds on: `docs/superpowers/specs/2026-06-15-actor-swarm-pi-extension-design.md`

## Goal

Tidy the subagents extension and add in-memory tracking of agent relationships
(message counts + spawn parentage) for a future visualizer. No new UI yet.

## A. Mechanical cleanups

- **Dead code:** remove `formatStatus` from `feed.ts` and its test from `feed.test.ts`.
  It is unused since the footer status was dropped.
- **English-only UI:** translate the German user-facing strings in `panel.ts`
  (`senden`, `schließen`, `kein Agent gewählt`, `keine Agents — mit spawn_agent erzeugen`,
  `noch keine Nachrichten`). Code comments stay German, consistent with the rest of the
  extension.
- **Rename the foreground agent `user` → `main`** everywhere: the `RESERVED` set, the
  user-sink indirection (bump the globalThis key versions so a stale pre-rename singleton
  from an earlier `/reload` cannot collide), `agentSystemPrompt`, the depth-0 record and its
  `spawnedBy`, every `name !== "user"` filter, the `kill` "cannot kill 'user'" guard, the
  panel filter, and the roster. Messages still read `[message from <sender>]`.

## B. Temp agent dir

Background sessions are pointed at an empty `agentDir` so they do not re-load this very
extension, skills, or AGENTS.md. The dir only needs to exist and stay empty.

Replace `fs.mkdtempSync(...)` (which leaks one empty dir per `/reload`) with a single stable
path created idempotently:

```
const blankAgentDir = path.join(os.tmpdir(), "pi-subagents-agentdir");
fs.mkdirSync(blankAgentDir, { recursive: true });
```

No cleanup logic needed — nothing is ever written there.

## C. Full toolset for spawned agents

`createSession` always leaves the built-in `tools` allowlist unset, so every spawned agent
inherits the full default foreground toolset plus the four custom agent tools via
`customTools`. The `tools` parameter on the `spawn_agent` tool schema is **removed** (it could
only restrict, which is now disallowed; YAGNI). `SpawnSpec.tools` and the `tools` plumbing in
`createSession`/`spawnAgent` are dropped accordingly.

## D. Spawned-by in the system prompt

Thread the spawner name from `spawnAgent` through `createSession` into `agentSystemPrompt`,
which appends a line: `You were spawned by "<spawner>".`

## E. Graph tracking (Engine, in-memory)

Add two fields to `Engine`, alongside the existing `events` log. They live in the
globalThis singleton: survive `/reload`, reset on pi restart.

```
private readonly messageEdges = new Map<string, Map<string, number>>(); // from -> (to -> count)
private readonly spawnParent  = new Map<string, string>();              // child -> parent
```

Behaviour:

- **Message counts:** in `route(from, to, content)`, after a successful deliver, increment
  `messageEdges[from][to]`. Covers normal sends, each target of a multicast (one increment
  per target), and the optional initial spawn message. `main` is a normal node.
- **Spawn parentage:** in `reserve(name, spawnerName)`, set `spawnParent[name] = spawnerName`.
  `main` is added via `addAgent` and has no parent entry (it is the root).
- **Re-spawn reset (full clean slate for X):** at the start of `reserve(X, …)`, before
  re-registering: delete `messageEdges[X]` (outgoing), delete the `X` key from every other
  node's inner map (incoming), then set the new `spawnParent[X]`.
- **Accessors** returning plain serializable snapshots (deep-copied, no live Map refs):
  - `getMessageMatrix(): Record<string, Record<string, number>>`
  - `getSpawnTree(): Record<string, string>`

No `/graph` command or panel yet — accessors only, for a future visualizer.

## Testing

Extend `engine.test.ts`:

- `route` increments the matrix; multicast increments one edge per target.
- `reserve` records the spawn parent.
- Re-spawning a killed name clears its incoming + outgoing edges and overwrites its parent.

Existing `node --test` suite must stay green (currently 36 tests).

## Out of scope

- Persisting the graph across pi restarts.
- Any visualization UI or `/graph` command.
- Per-agent turn caps or settings-bound caps.
