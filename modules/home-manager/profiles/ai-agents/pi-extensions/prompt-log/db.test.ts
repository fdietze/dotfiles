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
