import { test } from "node:test";
import assert from "node:assert/strict";
import {
  type AgentMessageLike,
  type BranchEntry,
  type Span,
  branchMessages,
  buildOverlay,
  planForget,
  planRemember,
  reconstructSpans,
  stripLeadingMarkers,
  unitBounds,
} from "./core.ts";

// --- branch builders -------------------------------------------------------

let ts = 0;
const entry = (
  id: string,
  role: string,
  content: AgentMessageLike["content"],
  extra: Partial<AgentMessageLike> = {},
): BranchEntry => ({
  type: "message",
  id,
  message: { role, content, timestamp: ++ts, ...extra },
});

const userE = (id: string, text: string) => entry(id, "user", text);
const asstText = (id: string, text: string) => entry(id, "assistant", text);
// Assistant turn that issues parallel tool calls.
const asstCalls = (id: string, callIds: string[]) =>
  entry(id, "assistant", [
    { type: "text", text: "working" },
    ...callIds.map((c) => ({ type: "toolCall", id: c }) as { type: string }),
  ] as AgentMessageLike["content"]);
const toolRes = (id: string, callId: string, text: string) =>
  entry(id, "toolResult", [{ type: "text", text }], { toolCallId: callId });

// A turn with N parallel reads in ONE assistant message + their results.
function batchedReadBranch(): BranchEntry[] {
  ts = 0;
  return [
    userE("u1", "read 3 files"),
    asstCalls("A", ["c1", "c2", "c3"]),
    toolRes("R1", "c1", "file 1 contents"),
    toolRes("R2", "c2", "file 2 contents"),
    toolRes("R3", "c3", "file 3 contents"),
    asstText("A2", "all read"),
  ];
}

// --- unitBounds ------------------------------------------------------------

test("unitBounds groups parallel tool calls of one assistant turn into one unit", () => {
  const msgs = branchMessages(batchedReadBranch());
  // order: u1(0) A(1) R1(2) R2(3) R3(4) A2(5)
  const { start, end } = unitBounds(msgs);
  assert.deepEqual(start, [0, 1, 1, 1, 1, 5]);
  assert.deepEqual(end, [0, 4, 4, 4, 4, 5]);
});

// --- planForget: the merge bug (regression) --------------------------------

test("planForget: two items hitting the same tool unit merge into ONE stub, keep the non-empty summary, count distinct", () => {
  const msgs = branchMessages(batchedReadBranch());
  // forget R1 with a summary AND R2 without one - both snap to the same unit.
  const plan = planForget(msgs, [], [
    { from: "R1", summary: "f01 done" },
    { from: "R2" },
  ]);
  assert.equal(plan.spans.length, 1, "one merged span");
  assert.deepEqual(plan.spans[0].memberIds, ["A", "R1", "R2", "R3"]);
  assert.equal(plan.spans[0].fromId, "A");
  assert.equal(plan.spans[0].summary, "f01 done", "empty summary must not clobber the real one");
  assert.deepEqual(plan.applied, ["A"], "deduplicated: one stub, not [A, A]");
  assert.equal(plan.collapsed, 4, "distinct members, not 4+4=8");
  assert.deepEqual(plan.summaries, ["f01 done"]);
});

test("planForget: single standalone message -> single-member span", () => {
  ts = 0;
  const branch = [userE("u1", "hi"), userE("u2", "a note"), asstText("a1", "ok")];
  const plan = planForget(branchMessages(branch), [], [{ from: "u2" }]);
  assert.equal(plan.spans.length, 1);
  assert.deepEqual(plan.spans[0].memberIds, ["u2"]);
  assert.equal(plan.spans[0].summary, "");
  assert.equal(plan.collapsed, 1);
});

test("planForget: summary present sets digest, absent leaves empty (drop)", () => {
  const msgs = branchMessages(batchedReadBranch());
  const withSum = planForget(msgs, [], [{ from: "A2", summary: "wrap up" }]);
  assert.equal(withSum.spans[0].summary, "wrap up");
  const noSum = planForget(msgs, [], [{ from: "A2" }]);
  assert.equal(noSum.spans[0].summary, "");
});

test("planForget: unknown ids reported, not applied", () => {
  const msgs = branchMessages(batchedReadBranch());
  const plan = planForget(msgs, [], [{ from: "nope" }, { from: "A2" }]);
  assert.deepEqual(plan.unknown, ["nope"]);
  assert.deepEqual(plan.applied, ["A2"]);
});

test("planForget: forgetting over an existing span absorbs it and inherits its summary", () => {
  const msgs = branchMessages(batchedReadBranch());
  const first = planForget(msgs, [], [{ from: "A2", summary: "kept" }]);
  // Now forget a wider range (u1..A2) - should absorb the A2 span and keep "kept".
  const second = planForget(msgs, first.spans, [
    { from: "u1", to: "A2", summary: "outer" },
  ]);
  assert.equal(second.spans.length, 1);
  assert.match(second.spans[0].summary, /kept/);
  assert.match(second.spans[0].summary, /outer/);
});

test("planForget: input spans are not mutated (pure)", () => {
  const msgs = branchMessages(batchedReadBranch());
  const input: Span[] = [];
  const plan = planForget(msgs, input, [{ from: "A2", summary: "x" }]);
  assert.equal(input.length, 0, "caller's array untouched");
  assert.equal(plan.spans.length, 1);
});

// --- planRemember ----------------------------------------------------------

test("planRemember: dissolves spans by fromId, reports unknown as noop, is pure", () => {
  const input: Span[] = [
    { fromId: "A", memberIds: ["A", "R1"], summary: "s" },
    { fromId: "u2", memberIds: ["u2"], summary: "" },
  ];
  const plan = planRemember(input, ["A", "missing"]);
  assert.deepEqual(plan.applied, ["A"]);
  assert.deepEqual(plan.noop, ["missing"]);
  assert.equal(plan.spans.length, 1);
  assert.equal(plan.spans[0].fromId, "u2");
  assert.equal(input.length, 2, "caller's array untouched");
});

// --- reconstructSpans ------------------------------------------------------

test("reconstructSpans: last custom entry wins; legacy `pruned` ids migrate to single-member spans", () => {
  const branch: BranchEntry[] = [
    { type: "custom", customType: "context-prune", data: { spans: [{ fromId: "X", memberIds: ["X"], summary: "old" }] } },
    { type: "custom", customType: "other", data: { spans: [] } },
    { type: "custom", customType: "context-prune", data: { pruned: ["p1", "p2"], spans: [{ fromId: "A", memberIds: ["A", "R1"], summary: "keep" }] } },
  ];
  const spans = reconstructSpans(branch);
  // latest entry: one real span + two migrated tombstones
  assert.equal(spans.length, 3);
  assert.deepEqual(spans[0], { fromId: "A", memberIds: ["A", "R1"], summary: "keep" });
  assert.deepEqual(spans[1], { fromId: "p1", memberIds: ["p1"], summary: "" });
  assert.deepEqual(spans[2], { fromId: "p2", memberIds: ["p2"], summary: "" });
});

// --- stripLeadingMarkers ---------------------------------------------------

test("stripLeadingMarkers: removes a leading run of [#8hex], keeps mid-prose references", () => {
  assert.equal(
    (stripLeadingMarkers({ role: "assistant", content: "[#abc12345] [#deadbeef] hi" }).content as string),
    "hi",
  );
  // mid-prose reference is preserved
  const keep = { role: "assistant", content: "see [#abc12345] there" };
  assert.equal(stripLeadingMarkers(keep).content, "see [#abc12345] there");
  // non-marker content returns the same object (no copy)
  const same = { role: "assistant", content: "plain" } as AgentMessageLike;
  assert.equal(stripLeadingMarkers(same), same);
});

test("stripLeadingMarkers: handles array content (first text block)", () => {
  const m: AgentMessageLike = {
    role: "assistant",
    content: [{ type: "text", text: "[#12345678] body" }],
  };
  const out = stripLeadingMarkers(m);
  assert.equal((out.content as Array<{ text?: string }>)[0].text, "body");
});

// --- buildOverlay ----------------------------------------------------------

// Clone the branch's messages into a plain list (like event.messages, no ids).
function messagesOf(branch: BranchEntry[]): AgentMessageLike[] {
  return branch
    .filter((e) => e.type === "message" && e.message)
    .map((e) => ({ ...(e.message as AgentMessageLike) }));
}

test("buildOverlay: tags taggable messages with their entry id", () => {
  const branch = batchedReadBranch();
  const out = buildOverlay(messagesOf(branch), branch, []);
  // user u1 gets a leading [#u1] marker
  assert.equal(out[0].content, "[#u1] read 3 files");
  // toolResult R1 text block prefixed
  const r1 = out[2].content as Array<{ text?: string }>;
  assert.match(r1[0].text as string, /^\[#R1\] /);
});

test("buildOverlay: a span replaces fromId with a stub and hides the other members", () => {
  const branch = batchedReadBranch();
  const span: Span = { fromId: "A", memberIds: ["A", "R1", "R2", "R3"], summary: "read 3 files" };
  const out = buildOverlay(messagesOf(branch), branch, [span]);
  // u1 (kept, tagged), then ONE stub for the whole unit, then A2.
  assert.equal(out.length, 3);
  assert.equal(out[1].role, "user");
  assert.equal(out[1].content, "[#A] (summary) read 3 files");
});

test("buildOverlay: empty-summary span renders a (forgotten N) stub", () => {
  const branch = batchedReadBranch();
  const span: Span = { fromId: "A", memberIds: ["A", "R1", "R2", "R3"], summary: "" };
  const out = buildOverlay(messagesOf(branch), branch, [span]);
  assert.equal(out[1].content, "[#A] (forgotten 4 messages)");
});
