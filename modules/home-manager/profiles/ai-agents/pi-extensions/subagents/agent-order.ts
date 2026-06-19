/**
 * Spawn-tree ordering of the agent list — pure, SDK-free, so it stays unit-testable.
 * Design: docs/superpowers/specs/2026-06-19-subagents-agent-list-ordering-design.md
 *
 * NOT a topological sort (that orders DAG dependencies). This is a spawn-tree pre-order
 * DFS: each parent is immediately followed by its whole subtree (contiguous). Communication
 * only orders siblings, so an agent sits close to who spawned it AND to its tightest parent
 * communication partner — as far as a 1D list allows (the full goal is Minimum Linear
 * Arrangement, NP-hard; the spawn tree is the stable backbone, comms order siblings only).
 */

export interface OrderableAgent {
	name: string;
	spawnedBy: string;
	createdAt: number;
}

/** Bidirectional message count between an agent and its parent (matrix is from->to->count). */
function parentTraffic(agent: OrderableAgent, matrix: Record<string, Record<string, number>>): number {
	const { name, spawnedBy } = agent;
	return (matrix[name]?.[spawnedBy] ?? 0) + (matrix[spawnedBy]?.[name] ?? 0);
}

export function orderAgents<T extends OrderableAgent>(
	agents: T[],
	matrix: Record<string, Record<string, number>>,
): T[] {
	const live = new Set(agents.map((x) => x.name));

	// Partition into roots (own parent = main, or parent no longer live = orphan) and children.
	const roots: T[] = [];
	const children = new Map<string, T[]>();
	for (const agent of agents) {
		const p = agent.spawnedBy;
		if (p === agent.name || !live.has(p)) {
			roots.push(agent);
		} else {
			const list = children.get(p);
			if (list) list.push(agent);
			else children.set(p, [agent]);
		}
	}

	// Siblings: heaviest parent-traffic first, then oldest, then name. Roots have no parent
	// traffic, so they sort by createdAt then name (main, the oldest, leads; orphans trail).
	const bySibling = (x: T, y: T): number =>
		parentTraffic(y, matrix) - parentTraffic(x, matrix) || x.createdAt - y.createdAt || x.name.localeCompare(y.name);
	const byRoot = (x: T, y: T): number => x.createdAt - y.createdAt || x.name.localeCompare(y.name);
	for (const list of children.values()) list.sort(bySibling);
	roots.sort(byRoot);

	// Pre-order DFS; the visited set makes a spawn cycle terminate.
	const result: T[] = [];
	const visited = new Set<string>();
	const visit = (agent: T): void => {
		if (visited.has(agent.name)) return;
		visited.add(agent.name);
		result.push(agent);
		for (const child of children.get(agent.name) ?? []) visit(child);
	};
	for (const root of roots) visit(root);

	// Safety: anything unreachable (disconnected or stuck in a cycle) is appended in
	// createdAt order, so the output is always a permutation of the input.
	if (result.length < agents.length) {
		for (const agent of [...agents].sort(byRoot)) if (!visited.has(agent.name)) visit(agent);
	}

	return result;
}
