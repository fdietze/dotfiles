/**
 * ETA formatting for agent status lines.
 *
 * The agent supplies a duration (etaMinutes); the extension converts it to an absolute
 * target timestamp (etaTs) at write time so the displayed clock time never goes stale.
 * Here we render that timestamp: a stable absolute anchor (~HH:MM, the source of truth)
 * plus a live-recomputed relative hint (in 45min) for at-a-glance freshness.
 *
 * Pure functional core — no clock access; the caller passes `now`.
 */

function pad2(n: number): string {
	return n < 10 ? `0${n}` : String(n);
}

/** Absolute clock time of the target as ~HH:MM (24-hour, zero-padded). */
function clock(etaTs: number): string {
	const d = new Date(etaTs);
	return `~${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** Remaining time as "in Xmin", or "in Xh Ym" when ≥ 60 min. Rounded to whole minutes. */
function remaining(ms: number): string {
	const mins = Math.round(ms / 60000);
	if (mins < 60) return `in ${mins}min`;
	const h = Math.floor(mins / 60);
	const m = mins % 60;
	return `in ${h}h ${m}min`;
}

/**
 * Render an ETA suffix for the status line, e.g.:
 *   future:  "ETA ~15:20 (in 45min)"
 *   overdue: "ETA ~15:20 (overdue)"   (now >= etaTs)
 * The absolute clock anchor is kept in both cases; only the parenthetical changes.
 */
export function formatEtaSuffix(etaTs: number, now: number): string {
	const hint = now >= etaTs ? "overdue" : remaining(etaTs - now);
	return `ETA ${clock(etaTs)} (${hint})`;
}

/**
 * Combine the agent's freeform status phrase with its ETA suffix into the display string
 * shown after the system status ("running tests · ETA ~15:20 (in 45min)"). Either part may
 * be absent: ETA without a phrase still renders; returns undefined when neither is set.
 * Shared by the panel roster and the snapshot so both render the ETA identically.
 */
export function formatCustomStatus(
	customStatus: string | undefined,
	etaTs: number | undefined,
	now: number,
): string | undefined {
	const eta = etaTs != null ? formatEtaSuffix(etaTs, now) : undefined;
	if (customStatus && eta) return `${customStatus} · ${eta}`;
	return customStatus || eta;
}
