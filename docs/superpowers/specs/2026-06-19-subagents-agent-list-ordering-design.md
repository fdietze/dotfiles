# Subagents agent-list ordering design

## Problem

The agent list (roster widget, `/agents` panel, `list_agents` tool) renders in
`engine.list()` insertion order (spawn order). In a deep swarm this scatters
related agents: a child can sit far from the parent that spawned it, and frequent
communication partners are not visually adjacent. Hard to orient.

## Goal

Order the agent list so each agent sits close to the agent that spawned it and to
its tightest communication partner — as far as a 1D list allows.

## Key insight / terminology

This is **not** a topological sort (that orders DAG dependencies). It is a
**spawn-tree pre-order DFS**: each parent is immediately followed by its entire
subtree (contiguous), and communication only orders siblings within a parent.

Placing both spawn-relatives and communication partners adjacent in a 1D list is
the Minimum Linear Arrangement problem (NP-hard) and the two goals conflict (a
child of main that messages a grandchild of a worker cannot be adjacent to it
without breaking subtree contiguity). Decision: the **spawn tree dominates** (the
stable backbone), communication orders only siblings. No full graph-layout
heuristic — overkill for <=8 agents and untestable.

## Decisions

- **Spawn tree dominates** (Approach A). DFS pre-order, subtree contiguous.
- **Siblings ordered by traffic with their parent**, descending — the child that
  communicates most with the parent sits closest to it (the parent is the row
  immediately before the sibling group).
- **Traffic is bidirectional**: `matrix[child][parent] + matrix[parent][child]`.
- **Tiebreak**: `createdAt` ascending, then `name` ascending (deterministic).
- `engine.list()` stays insertion order (membership); ordering happens in the
  consumption layer (SoC).

## Architecture

New file `agent-order.ts` (dedicated concern, dedicated test file) — a pure
function, no pi/SDK dependency, so it is trivially unit-testable.

```ts
export interface OrderableAgent {
  name: string;
  spawnedBy: string;
  createdAt: number;
}

/**
 * Spawn-tree pre-order DFS. Each parent is immediately followed by its whole
 * subtree. Siblings are ordered by descending bidirectional traffic with their
 * parent (matrix[child][parent] + matrix[parent][child]); ties broken by
 * createdAt asc then name asc. Roots (agents whose spawnedBy is themselves —
 * "main" — or whose parent is no longer live — orphans) are ordered by createdAt
 * asc then name asc. A visited set guards against spawn cycles; any agent never
 * reached is appended at the end in createdAt asc order.
 */
export function orderAgents<T extends OrderableAgent>(
  agents: T[],
  matrix: Record<string, Record<string, number>>,
): T[];
```

### Algorithm

1. `live` = set of agent names; `byName` map.
2. Partition: for each agent `a`, let `p = a.spawnedBy`. If `p === a.name` (main)
   or `!live.has(p)` (orphan: parent killed) → `roots`. Else → `children[p]`.
3. `parentTraffic(a) = (matrix[a.name]?.[a.spawnedBy] ?? 0) + (matrix[a.spawnedBy]?.[a.name] ?? 0)`.
4. Sibling comparator: `parentTraffic` desc, then `createdAt` asc, then `name` asc.
   Root comparator: `createdAt` asc, then `name` asc (main, oldest, comes first;
   orphans trail).
5. DFS from each sorted root with a `visited` set; push node, then recurse its
   sorted children. The visited set makes a cycle terminate.
6. Safety: append any agent not in `visited` (disconnected or cycle remnant) in
   `createdAt` asc order, so the output is always a permutation of the input.

### Integration (3 call sites)

Each render site orders before rendering, passing the live matrix:

- `index.ts` `updateStatus` (roster widget): `orderAgents(engine.list(),
  engine.getMessageMatrix())`, then filter out `main` as today (relative order of
  background agents preserved).
- `panel.ts` `agents()` accessor: order the list the panel iterates/selects.
- `index.ts` `list_agents` tool: order before `formatSnapshot(...)`
  (formatSnapshot keeps its signature; it receives the already-ordered list).

`engine.list()` is unchanged. No new engine method (avoids an engine→agent-order
import cycle); ordering is a consumption-layer concern.

## Testing (`agent-order.test.ts`)

The ordering function must be thoroughly unit-tested:

- **Linear chain**: main→a→b→c yields `[main, a, b, c]`.
- **Siblings by parent traffic**: main spawns x, y, z; matrix has main↔y heaviest
  → `y` first among siblings.
- **Subtree contiguity**: main spawns a, b; a spawns a1, a2 → `a, a1, a2` appear
  contiguously before `b`.
- **Bidirectional traffic**: child→parent only vs parent→child only vs both sum
  correctly; a pair heavy in one direction outranks a quieter pair.
- **Tiebreak**: equal traffic → `createdAt` asc; equal createdAt → `name` asc.
- **Orphan**: agent whose `spawnedBy` is not live becomes a root and trails main
  (later createdAt), its own subtree still contiguous under it.
- **Cycle guard**: synthetic spawn cycle (a.spawnedBy=b, b.spawnedBy=a) →
  terminates, every agent appears exactly once.
- **Output is a permutation**: same multiset of agents in, out (no drops/dupes) —
  assert for every case.
- **Empty list** → `[]`; **only main** → `[main]`.
- **Stability**: all keys equal → input/createdAt order preserved.

## Out of scope

- Full graph linear-arrangement heuristic (cross-subtree communication locality).
- Sibling-to-sibling clustering (only parent traffic orders siblings).
- Re-rooting orphans under `main` (they become top-level roots instead — simpler,
  no special-case branch).
- Changing `engine.list()` order.
