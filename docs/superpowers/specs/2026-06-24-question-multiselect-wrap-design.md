# Question extension: always multi-select + text wrapping

Date: 2026-06-24
File: `modules/home-manager/profiles/ai-agents/pi-extensions/question.ts`

## Problem

Current `question` tool is single-select (one option per Enter) and truncates
all text to terminal width (`truncateToWidth`). Long questions/labels get cut
off; the agent cannot collect a multi-option answer.

## Goal

1. **Always multi-select.** Every question is checkbox-style; user picks 0..n
   options. No agent-facing param — multi-select is unconditional.
2. **Custom note field** below the checkboxes, combinable with checked options
   (replaces the old "Type something." selectable row).
3. **Wrap, not truncate.** Question text, option labels, descriptions, and note
   wrap to terminal width via `wrapTextWithAnsi`. The accent separator stays
   full-width.

## Layout (top → bottom)

```
──────────────────────────  (accent separator, full width)
 <question text, wrapped>

 [ ] 1. Option A
       <description, wrapped, muted>
 [x] 2. Option B
 [ ] 3. Option C

 Note: <editable text field>     ← focused + edit-active on open
 ──────
 <hint line>
──────────────────────────
```

## Interaction model

- **On open:** focus on the **Note field, edit mode active**. Typing fills note.
- `Enter` (anywhere, incl. edit mode) → **submit whole set** = checked options +
  note text. Universal submit. Note is single-line.
- `Esc` from edit mode → exit to **navigation** (cursor stays on note row).
- `↑/↓` in navigation → move across option rows + the note row.
- `Space` on an option row → toggle its checkbox.
- `Space` or typing on the note row → (re)enter edit mode.
- `Esc` from navigation → **cancel**. (From edit: first Esc → nav, second → cancel.)
- **Empty submit** (nothing checked, empty note) → **valid deliberate answer**,
  NOT cancel. Cancel is exclusively `Esc`.

## Result reporting

`content` (text the agent reads):
- Has selection and/or note:
  `User selected: 1. Foo, 3. Bar | note: <text>` — omit the missing side.
- Empty submit: `User submitted empty answer (no options, no note)`.
- Cancel: `User cancelled the selection`.

`details` schema (replaces old single `answer`):

```ts
interface QuestionDetails {
  question: string;
  options: string[];   // all offered labels
  selected: string[];  // checked labels
  note: string | null; // custom note text, null if empty
  cancelled: boolean;
}
```

## Rendering helpers

- `wrapTextWithAnsi(str, width)` for question, labels, descriptions, note.
  Reapply style per wrapped line (styles do not carry across lines per tui.md).
- `renderCall`: drop "Type something."; show options list + "(+ custom note)".
- `renderResult`: show checked list + note, or `Cancelled` when cancelled.

## Params — unchanged

Same `question: string` + `options: [{label, description?}]`. No new params.
KISS / YAGNI: multi-select always on, note always present.

## Non-interactive / empty-options guards — unchanged

- `ctx.mode !== "tui"` → error result, `cancelled: true`.
- `options.length === 0` is now allowed (user can still submit a note or empty).
  Keep working when no options are supplied.
</content>
</invoke>
