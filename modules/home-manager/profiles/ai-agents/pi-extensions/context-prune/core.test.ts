import { test } from "node:test";
import assert from "node:assert/strict";
import {
  type AgentMessageLike,
  type BranchEntry,
  type Span,
  branchMessages,
  buildOverlay,
  estimateTokens,
  fmtTokens,
  planCollapse,
  planExpand,
  reconstructSpans,
  serializeSpan,
  stripLeadingMarkers,
  summarizeTree,
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

// Five standalone user messages (no tool units) -> splittable span.
function fiveUserBranch(): BranchEntry[] {
  ts = 0;
  return [
    userE("u1", "one"),
    userE("u2", "two two"),
    userE("u3", "three three three"),
    userE("u4", "four four four four"),
    userE("u5", "five"),
  ];
}

// --- estimateTokens / fmtTokens -------------------------------------------

test("estimateTokens: chars/4 over string and over text+toolCall blocks", () => {
  assert.equal(estimateTokens({ role: "user", content: "x".repeat(40) }), 10);
  // "ab"(2) + name "read"(4) + JSON.stringify({path:"f"}) '{"path":"f"}'(12) = 18 -> ceil/4 = 5
  const a: AgentMessageLike = {
    role: "assistant",
    content: [
      { type: "text", text: "ab" },
      { type: "toolCall", name: "read", arguments: { path: "f" } },
    ] as AgentMessageLike["content"],
  };
  assert.equal(estimateTokens(a), 5);
});

test("fmtTokens: raw below 1000, k-suffix with trailing .0 dropped", () => {
  assert.equal(fmtTokens(0), "0");
  assert.equal(fmtTokens(999), "999");
  assert.equal(fmtTokens(1000), "1k");
  assert.equal(fmtTokens(1200), "1.2k");
  assert.equal(fmtTokens(3400), "3.4k");
  assert.equal(fmtTokens(12000), "12k");
});

// --- unitBounds ------------------------------------------------------------

test("unitBounds groups parallel tool calls of one assistant turn into one unit", () => {
  const msgs = branchMessages(batchedReadBranch());
  const { start, end } = unitBounds(msgs);
  assert.deepEqual(start, [0, 1, 1, 1, 1, 5]);
  assert.deepEqual(end, [0, 4, 4, 4, 4, 5]);
});

// --- planCollapse ----------------------------------------------------------

test("planCollapse: two items hitting the same tool unit merge into ONE stub, keep the non-empty summary, count distinct", () => {
  const msgs = branchMessages(batchedReadBranch());
  const plan = planCollapse(msgs, [], [
    { from: "R1", summary: "f01 done" },
    { from: "R2" },
  ]);
  assert.equal(plan.spans.length, 1, "one merged span");
  assert.deepEqual(plan.spans[0].memberIds, ["A", "R1", "R2", "R3"]);
  assert.equal(plan.spans[0].fromId, "A");
  assert.equal(plan.spans[0].summary, "f01 done");
  assert.deepEqual(plan.applied, ["A"]);
  assert.equal(plan.collapsed, 4);
  assert.deepEqual(plan.summaries, ["f01 done"]);
});

test("planCollapse: freedTokens > 0 for a fresh fold, and excludes already-folded members", () => {
  const msgs = branchMessages(batchedReadBranch());
  const first = planCollapse(msgs, [], [{ from: "R1" }]);
  assert.ok(first.freedTokens > 0, "fresh fold frees tokens");
  // re-collapsing the identical (already folded) range frees no new live tokens
  const second = planCollapse(msgs, first.spans, [{ from: "R1" }]);
  assert.ok(second.freedTokens <= 0, "no double-counting already-folded members");
});

test("planCollapse: single standalone message -> single-member span", () => {
  const plan = planCollapse(branchMessages(fiveUserBranch()), [], [{ from: "u2" }]);
  assert.equal(plan.spans.length, 1);
  assert.deepEqual(plan.spans[0].memberIds, ["u2"]);
  assert.equal(plan.spans[0].summary, "");
  assert.equal(plan.collapsed, 1);
});

test("planCollapse: unknown ids reported, not applied", () => {
  const msgs = branchMessages(batchedReadBranch());
  const plan = planCollapse(msgs, [], [{ from: "nope" }, { from: "A2" }]);
  assert.deepEqual(plan.unknown, ["nope"]);
  assert.deepEqual(plan.applied, ["A2"]);
});

test("planCollapse: folding over an existing span absorbs it and inherits its summary", () => {
  const msgs = branchMessages(fiveUserBranch());
  const first = planCollapse(msgs, [], [{ from: "u5", summary: "kept" }]);
  const second = planCollapse(msgs, first.spans, [
    { from: "u1", to: "u5", summary: "outer" },
  ]);
  assert.equal(second.spans.length, 1);
  assert.match(second.spans[0].summary, /kept/);
  assert.match(second.spans[0].summary, /outer/);
});

test("planCollapse: input spans are not mutated (pure)", () => {
  const msgs = branchMessages(batchedReadBranch());
  const input: Span[] = [];
  const plan = planCollapse(msgs, input, [{ from: "A2", summary: "x" }]);
  assert.equal(input.length, 0);
  assert.equal(plan.spans.length, 1);
});

// --- planExpand (range-aware, splits) --------------------------------------

test("planExpand: bare span fromId expands the whole fold", () => {
  const msgs = branchMessages(fiveUserBranch());
  const folded = planCollapse(msgs, [], [{ from: "u1", to: "u5", summary: "s" }]);
  const plan = planExpand(msgs, folded.spans, [{ from: "u1" }]);
  assert.equal(plan.spans.length, 0, "fold fully dissolved");
  assert.deepEqual(plan.applied, ["u1"]);
  assert.ok(plan.restoredTokens > 0);
});

test("planExpand: sub-range splits the fold into two remnants that inherit the summary", () => {
  const msgs = branchMessages(fiveUserBranch());
  const folded = planCollapse(msgs, [], [{ from: "u1", to: "u5", summary: "s" }]);
  const plan = planExpand(msgs, folded.spans, [{ from: "u3", to: "u3" }]);
  assert.deepEqual(plan.applied, ["u3"]);
  assert.equal(plan.spans.length, 2);
  const byFrom = Object.fromEntries(plan.spans.map((s) => [s.fromId, s]));
  assert.deepEqual(byFrom["u1"].memberIds, ["u1", "u2"]);
  assert.deepEqual(byFrom["u4"].memberIds, ["u4", "u5"]);
  assert.equal(byFrom["u1"].summary, "s");
  assert.equal(byFrom["u4"].summary, "s");
  assert.equal(plan.restoredTokens, estimateTokens({ role: "user", content: "three three three" }));
});

test("planExpand: sub-range snaps to whole tool units (no orphaned pair)", () => {
  const msgs = branchMessages(batchedReadBranch());
  const folded = planCollapse(msgs, [], [{ from: "u1", to: "A2", summary: "s" }]);
  // try to expand just R2 (inside the A..R3 unit) -> snaps to the whole unit
  const plan = planExpand(msgs, folded.spans, [{ from: "R2", to: "R2" }]);
  // the restored chunk must be the whole unit A,R1,R2,R3; remnants are u1 and A2
  const fromsRestoredUnit = plan.applied[0];
  assert.equal(fromsRestoredUnit, "A");
  const remnants = plan.spans.flatMap((s) => s.memberIds).sort();
  assert.deepEqual(remnants, ["A2", "u1"]);
});

test("planExpand: id matching no span is a noop", () => {
  const msgs = branchMessages(fiveUserBranch());
  const folded = planCollapse(msgs, [], [{ from: "u1", to: "u2", summary: "s" }]);
  const plan = planExpand(msgs, folded.spans, [{ from: "u5" }]);
  assert.deepEqual(plan.noop, ["u5"]);
  assert.equal(plan.spans.length, 1);
});

// --- summarizeTree ---------------------------------------------------------

test("summarizeTree: totals + one line per span in branch order", () => {
  const msgs = branchMessages(fiveUserBranch());
  const spans: Span[] = [
    { fromId: "u4", memberIds: ["u4", "u5"], summary: "" },
    { fromId: "u1", memberIds: ["u1", "u2"], summary: "early notes" },
  ];
  const t = summarizeTree(spans, msgs);
  assert.equal(t.totalSpans, 2);
  assert.ok(t.hiddenTokens > 0);
  // ordered by first-member position: u1 span before u4 span
  assert.match(t.lines[0], /^\[#u1\] · 2 msgs · \S+ · early notes$/);
  assert.match(t.lines[1], /^\[#u4\] · 2 msgs · \S+ · \(no summary\)$/);
});

// --- serializeSpan ---------------------------------------------------------

test("serializeSpan: members with inner id + role + size + content, capped", () => {
  const msgs = branchMessages(fiveUserBranch());
  const span: Span = { fromId: "u2", memberIds: ["u2", "u3"], summary: "" };
  const out = serializeSpan(span, msgs);
  assert.match(out, /\[#u2\] user \d+\ntwo two/);
  assert.match(out, /\[#u3\] user \d+\nthree three three/);
});

test("serializeSpan: long content is truncated with a marker", () => {
  ts = 0;
  const branch = [userE("big", "z".repeat(5000))];
  const span: Span = { fromId: "big", memberIds: ["big"], summary: "" };
  const out = serializeSpan(span, branchMessages(branch), 2000);
  assert.match(out, /… \[\+3000 chars\]$/);
});

// --- reconstructSpans ------------------------------------------------------

test("reconstructSpans: last custom entry wins; legacy `pruned` ids migrate to single-member spans", () => {
  const branch: BranchEntry[] = [
    { type: "custom", customType: "context-prune", data: { spans: [{ fromId: "X", memberIds: ["X"], summary: "old" }] } },
    { type: "custom", customType: "other", data: { spans: [] } },
    { type: "custom", customType: "context-prune", data: { pruned: ["p1", "p2"], spans: [{ fromId: "A", memberIds: ["A", "R1"], summary: "keep" }] } },
  ];
  const spans = reconstructSpans(branch);
  assert.equal(spans.length, 3);
  assert.deepEqual(spans[0], { fromId: "A", memberIds: ["A", "R1"], summary: "keep" });
  assert.deepEqual(spans[1], { fromId: "p1", memberIds: ["p1"], summary: "" });
  assert.deepEqual(spans[2], { fromId: "p2", memberIds: ["p2"], summary: "" });
});

// --- stripLeadingMarkers ---------------------------------------------------

test("stripLeadingMarkers: removes a leading run of [#8hex] incl. sized form, keeps mid-prose references", () => {
  assert.equal(
    stripLeadingMarkers({ role: "assistant", content: "[#abc12345] [#deadbeef] hi" }).content,
    "hi",
  );
  // sized markers are stripped too
  assert.equal(
    stripLeadingMarkers({ role: "assistant", content: "[#abc12345 1.2k] [#deadbeef 340] hi" }).content,
    "hi",
  );
  const keep = { role: "assistant", content: "see [#abc12345] there" };
  assert.equal(stripLeadingMarkers(keep).content, "see [#abc12345] there");
  const same = { role: "assistant", content: "plain" } as AgentMessageLike;
  assert.equal(stripLeadingMarkers(same), same);
});

// --- buildOverlay ----------------------------------------------------------

function messagesOf(branch: BranchEntry[]): AgentMessageLike[] {
  return branch
    .filter((e) => e.type === "message" && e.message)
    .map((e) => ({ ...(e.message as AgentMessageLike) }));
}

test("buildOverlay: tags taggable messages with a sized [#id N] marker", () => {
  const branch = batchedReadBranch();
  const out = buildOverlay(messagesOf(branch), branch, []);
  assert.match(out[0].content as string, /^\[#u1 \d+\] read 3 files$/);
  const r1 = out[2].content as Array<{ text?: string }>;
  assert.match(r1[0].text as string, /^\[#R1 \d+\] /);
});

test("buildOverlay: a summarized span renders a stub with hidden cost and hides members", () => {
  const branch = batchedReadBranch();
  const span: Span = { fromId: "A", memberIds: ["A", "R1", "R2", "R3"], summary: "read 3 files" };
  const out = buildOverlay(messagesOf(branch), branch, [span]);
  assert.equal(out.length, 3);
  assert.equal(out[1].role, "user");
  assert.match(out[1].content as string, /^\[#A\] \(summary, \S+ hidden\) read 3 files$/);
});

test("buildOverlay: empty-summary span renders a (forgotten N, X hidden) stub", () => {
  const branch = batchedReadBranch();
  const span: Span = { fromId: "A", memberIds: ["A", "R1", "R2", "R3"], summary: "" };
  const out = buildOverlay(messagesOf(branch), branch, [span]);
  assert.match(out[1].content as string, /^\[#A\] \(forgotten 4 messages, \S+ hidden\)$/);
});
