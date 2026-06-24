/**
 * ETA formatting for agent status lines.
 *
 * The agent supplies a duration (etaMinutes); the extension converts it to an absolute
 * target timestamp (etaTs) at write time. Here we render that timestamp as a static
 * absolute clock anchor (~HH:MM). Deliberately no relative hint ("in 45min") and no
 * "overdue" marker: both are now-derived and would silently go stale between renders,
 * so the display is fully time-independent and never needs a refresh tick.
 */

function pad2(n: number): string {
	return n < 10 ? `0${n}` : String(n);
}

/** Absolute clock time of the target as ~HH:MM (24-hour, zero-padded). */
function clock(etaTs: number): string {
	const d = new Date(etaTs);
	return `~${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

/** Render an ETA suffix for the status line, e.g. "ETA ~15:20". Static — no now needed. */
export function formatEtaSuffix(etaTs: number): string {
	return `ETA ${clock(etaTs)}`;
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
): string | undefined {
	const eta = etaTs != null ? formatEtaSuffix(etaTs) : undefined;
	if (customStatus && eta) return `${customStatus} · ${eta}`;
	return customStatus || eta;
}
