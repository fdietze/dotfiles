import { test } from "node:test";
import assert from "node:assert";
import { openDb, logPrompt } from "./db.ts";

test("logPrompt inserts a row and returns true", () => {
  const db = openDb(":memory:");
  const inserted = logPrompt(db, {
    ts_ms: 1000, cwd: "/p", session_id: "s1", source_tool: "pi", source: "interactive", text: "hello world",
  });
  assert.equal(inserted, true);
  const row = db.prepare("SELECT * FROM prompts").get() as any;
  assert.equal(row.text, "hello world");
  assert.equal(row.source_tool, "pi");
  assert.equal(row.starred, 0);
});

test("dedup on (source_tool, session_id, text): second insert ignored", () => {
  const db = openDb(":memory:");
  const p = { ts_ms: 1, session_id: "s1", source_tool: "pi", text: "same" };
  assert.equal(logPrompt(db, { ...p, ts_ms: 1 }), true);
  assert.equal(logPrompt(db, { ...p, ts_ms: 2 }), false); // drifted ts still dedups
  assert.equal((db.prepare("SELECT COUNT(*) c FROM prompts").get() as any).c, 1);
});

test("same text in different session is not deduped", () => {
  const db = openDb(":memory:");
  logPrompt(db, { ts_ms: 1, session_id: "s1", source_tool: "pi", text: "x" });
  logPrompt(db, { ts_ms: 1, session_id: "s2", source_tool: "pi", text: "x" });
  assert.equal((db.prepare("SELECT COUNT(*) c FROM prompts").get() as any).c, 2);
});

import { searchPrompts, setStar, setTags } from "./db.ts";

function seed() {
  const db = openDb(":memory:");
  logPrompt(db, { ts_ms: 10, hostname: "h1", cwd: "/a/proj", session_id: "s1", source_tool: "pi", text: "firefox stylix color theme" });
  logPrompt(db, { ts_ms: 20, hostname: "h2", cwd: "/b", session_id: "s2", source_tool: "claude", text: "enable colorTheme option" });
  logPrompt(db, { ts_ms: 30, hostname: "h1", cwd: "/a/proj", session_id: "s3", source_tool: "codex", text: "unrelated note" });
  return db;
}

test("FTS query matches by token, ranked", () => {
  const rows = searchPrompts(seed(), { query: "stylix" });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].source_tool, "pi");
});

test("FTS query tolerates punctuation without throwing", () => {
  const rows = searchPrompts(seed(), { query: 'color "theme"' });
  assert.ok(rows.length >= 1);
});

test("no query returns most recent first", () => {
  const rows = searchPrompts(seed(), {});
  assert.equal(rows[0].ts_ms, 30);
});

test("filters: tool, host, project, since, starred", () => {
  const db = seed();
  assert.equal(searchPrompts(db, { filters: { tool: "claude" } }).length, 1);
  assert.equal(searchPrompts(db, { filters: { host: "h1" } }).length, 2);
  assert.equal(searchPrompts(db, { filters: { project: "proj" } }).length, 2);
  assert.equal(searchPrompts(db, { filters: { since: 25 } }).length, 1);
  const id = searchPrompts(db, { query: "stylix" })[0].id;
  setStar(db, id, true);
  assert.equal(searchPrompts(db, { filters: { starred: true } }).length, 1);
});

test("setTags round-trips and text is never mutated", () => {
  const db = seed();
  const row = searchPrompts(db, { query: "stylix" })[0];
  setTags(db, row.id, "good reusable");
  const after = searchPrompts(db, { query: "stylix" })[0];
  assert.equal(after.tags, "good reusable");
  assert.equal(after.text, row.text);
});
