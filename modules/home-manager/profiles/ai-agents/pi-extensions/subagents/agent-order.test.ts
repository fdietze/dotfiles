import { test } from "node:test";
import assert from "node:assert/strict";
import { orderAgents, type OrderableAgent } from "./agent-order.ts";

// Compact agent builder: name, spawnedBy, createdAt (defaults to insertion via counter).
let clock = 0;
const a = (name: string, spawnedBy: string, createdAt = clock++): OrderableAgent => ({ name, spawnedBy, createdAt });
const names = (xs: OrderableAgent[]): string[] => xs.map((x) => x.name);

test("linear chain: parent immediately followed by its descendant", () => {
	const agents = [a("main", "main", 0), a("a", "main", 1), a("b", "a", 2), a("c", "b", 3)];
	assert.deepEqual(names(orderAgents(agents, {})), ["main", "a", "b", "c"]);
});

test("siblings ordered by descending traffic with the parent", () => {
	const agents = [a("main", "main", 0), a("x", "main", 1), a("y", "main", 2), a("z", "main", 3)];
	// y talks most with main (5+2=7), x a little (0+1=1), z none.
	const matrix = { main: { y: 5, x: 1 }, y: { main: 2 } };
	assert.deepEqual(names(orderAgents(agents, matrix)), ["main", "y", "x", "z"]);
});

test("subtree is contiguous: a's children come before sibling b", () => {
	const agents = [a("main", "main", 0), a("a", "main", 1), a("b", "main", 2), a("a1", "a", 3), a("a2", "a", 4)];
	assert.deepEqual(names(orderAgents(agents, {})), ["main", "a", "a1", "a2", "b"]);
});

test("parent traffic is bidirectional (child->parent + parent->child)", () => {
	const agents = [a("main", "main", 0), a("p", "main", 1), a("q", "main", 2), a("r", "main", 3)];
	// p: only child->parent (3); q: only parent->child (4); r: both (2+5=7).
	const matrix = { p: { main: 3 }, main: { q: 4, r: 5 }, r: { main: 2 } };
	assert.deepEqual(names(orderAgents(agents, matrix)), ["main", "r", "q", "p"]);
});

test("tiebreak: equal traffic -> createdAt asc", () => {
	const agents = [a("main", "main", 0), a("late", "main", 5), a("early", "main", 1)];
	assert.deepEqual(names(orderAgents(agents, {})), ["main", "early", "late"]);
});

test("tiebreak: equal traffic and createdAt -> name asc", () => {
	const agents = [a("main", "main", 0), a("d", "main", 1), a("c", "main", 1)];
	assert.deepEqual(names(orderAgents(agents, {})), ["main", "c", "d"]);
});

test("orphan (parent not live) becomes a root and trails main, subtree intact", () => {
	const agents = [a("main", "main", 0), a("w", "main", 1), a("o", "dead", 2), a("o1", "o", 3)];
	assert.deepEqual(names(orderAgents(agents, {})), ["main", "w", "o", "o1"]);
});

test("cycle with no root: terminates, every agent exactly once", () => {
	const agents = [a("x", "y", 0), a("y", "x", 1)];
	const out = orderAgents(agents, {});
	assert.equal(out.length, 2);
	assert.deepEqual([...names(out)].sort(), ["x", "y"]);
});

test("cycle unreachable from main: main subtree first, cycle appended once each", () => {
	const agents = [a("main", "main", 0), a("a", "main", 1), a("b", "c", 2), a("c", "b", 3)];
	const out = names(orderAgents(agents, {}));
	assert.deepEqual(out.slice(0, 2), ["main", "a"]);
	assert.deepEqual([...out].sort(), ["a", "b", "c", "main"]);
});

test("output is always a permutation of the input (no drops/dupes)", () => {
	const agents = [a("main", "main", 0), a("a", "main", 1), a("b", "a", 2), a("o", "ghost", 3)];
	const out = orderAgents(agents, { a: { main: 1 }, b: { a: 2 } });
	assert.deepEqual([...names(out)].sort(), [...names(agents)].sort());
	assert.equal(out.length, agents.length);
});

test("empty list -> empty; only main -> [main]", () => {
	assert.deepEqual(names(orderAgents([], {})), []);
	assert.deepEqual(names(orderAgents([a("main", "main", 0)], {})), ["main"]);
});
