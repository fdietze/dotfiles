// Pure logic for the question tool: result formatting + cursor bounds.
// Functional core — no TUI/IO — so it is unit-testable with node:test.

export interface ResultModel {
	selected: string[]; // checked option labels, in original order
	note: string | null; // trimmed custom note, null if empty
	content: string; // text the agent reads
	isEmpty: boolean; // nothing checked and no note (still a valid submit)
}

// Build the agent-facing result. Numbering uses the ORIGINAL 1-based option
// index so the agent can map an answer back to the option it offered.
export function formatResult(labels: string[], checked: boolean[], noteText: string): ResultModel {
	const selected: string[] = [];
	const selParts: string[] = [];
	for (let i = 0; i < labels.length; i++) {
		if (checked[i]) {
			selected.push(labels[i]);
			selParts.push(`${i + 1}. ${labels[i]}`);
		}
	}
	const trimmed = noteText.trim();
	const note = trimmed.length > 0 ? trimmed : null;
	const selStr = selParts.join(", ");

	let content: string;
	if (selected.length > 0 && note !== null) {
		content = `User selected: ${selStr} | note: ${note}`;
	} else if (selected.length > 0) {
		content = `User selected: ${selStr}`;
	} else if (note !== null) {
		content = `User note: ${note}`;
	} else {
		content = "User submitted empty answer (no options, no note)";
	}

	return { selected, note, content, isEmpty: selected.length === 0 && note === null };
}

// Rows are: option rows 0..optionCount-1, then the note row at index optionCount.
export function clampCursor(cursor: number, optionCount: number): number {
	if (cursor < 0) return 0;
	if (cursor > optionCount) return optionCount;
	return cursor;
}

export function isNoteRow(cursor: number, optionCount: number): boolean {
	return cursor === optionCount;
}
