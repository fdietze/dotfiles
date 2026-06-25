/**
 * web_fetch backend: URL -> clean markdown via Jina Reader (r.jina.ai, no key),
 * fronted by a non-negotiable SSRF guard.
 *
 * The guard validates the AGENT-supplied target URL before we touch the
 * network, so web_fetch can never be turned into a probe of internal services
 * (localhost, RFC1918/link-local/ULA), non-http(s) schemes, oversized bodies,
 * unexpected content types, or redirect chains.
 */

import { lookup } from "node:dns/promises";

const MAX_BYTES = 2 * 1024 * 1024; // 2 MB
const MAX_REDIRECTS = 3;
const ALLOWED_CONTENT = [/^text\//i, /^application\/json/i, /\bmarkdown\b/i, /\bxml\b/i];
const UA = "pi-web-search/1.0";

/** True for loopback / private / link-local / ULA / unspecified addresses. */
export function isPrivateIp(ip: string): boolean {
	const v = ip.toLowerCase();
	// IPv6 (incl. IPv4-mapped ::ffff:a.b.c.d)
	if (v.includes(":")) {
		if (v === "::1" || v === "::" || v === "::0") return true;
		if (v.startsWith("fe80") || v.startsWith("fc") || v.startsWith("fd")) return true;
		const mapped = v.match(/::ffff:(\d+\.\d+\.\d+\.\d+)$/);
		if (mapped) return isPrivateIp(mapped[1]);
		return false;
	}
	const o = v.split(".").map(Number);
	if (o.length !== 4 || o.some((n) => Number.isNaN(n) || n < 0 || n > 255)) return true; // malformed -> reject
	const [a, b] = o;
	if (a === 0 || a === 127) return true; // unspecified / loopback
	if (a === 10) return true;
	if (a === 172 && b >= 16 && b <= 31) return true;
	if (a === 192 && b === 168) return true;
	if (a === 169 && b === 254) return true; // link-local
	if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
	return false;
}

/** Throws if the URL is not a safe public http(s) target. */
async function assertSafeTarget(raw: string): Promise<URL> {
	let url: URL;
	try {
		url = new URL(raw);
	} catch {
		throw new Error(`Invalid URL: ${raw}`);
	}
	if (url.protocol !== "http:" && url.protocol !== "https:")
		throw new Error(`Blocked scheme '${url.protocol}'. Only http/https allowed.`);
	const host = url.hostname.toLowerCase();
	if (host === "localhost" || host.endsWith(".localhost"))
		throw new Error("Blocked: localhost is not a permitted target.");
	// Resolve every address the host maps to; reject if ANY is private.
	const addrs = await lookup(host, { all: true }).catch(() => {
		throw new Error(`DNS resolution failed for ${host}`);
	});
	for (const { address } of addrs)
		if (isPrivateIp(address)) throw new Error(`Blocked: ${host} resolves to private address ${address}.`);
	return url;
}

/** Read a response body up to MAX_BYTES, aborting if it grows past the cap. */
async function readCapped(res: Response): Promise<string> {
	const len = Number(res.headers.get("content-length") ?? "0");
	if (len > MAX_BYTES) throw new Error(`Response too large (${len} bytes > ${MAX_BYTES}).`);
	const reader = res.body?.getReader();
	if (!reader) return "";
	const chunks: Uint8Array[] = [];
	let total = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		total += value.length;
		if (total > MAX_BYTES) {
			await reader.cancel();
			throw new Error(`Response exceeded ${MAX_BYTES} bytes.`);
		}
		chunks.push(value);
	}
	return Buffer.concat(chunks).toString("utf8");
}

/**
 * Fetch `targetUrl` as markdown via Jina Reader. Validates the target first,
 * follows at most MAX_REDIRECTS hops manually (re-validating each), and caps
 * size + content type.
 */
export async function fetchAsMarkdown(targetUrl: string, signal?: AbortSignal): Promise<string> {
	await assertSafeTarget(targetUrl);
	let current = `https://r.jina.ai/${targetUrl}`;
	for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
		const res: Response = await fetch(current, {
			redirect: "manual",
			headers: { "User-Agent": UA, Accept: "text/markdown, text/plain, */*" },
			signal,
		});
		if (res.status >= 300 && res.status < 400) {
			const loc = res.headers.get("location");
			if (!loc) throw new Error(`Redirect (${res.status}) without Location header.`);
			current = new URL(loc, current).toString();
			continue;
		}
		if (!res.ok) throw new Error(`Fetch failed: ${res.status} ${res.statusText}`);
		const ct = res.headers.get("content-type") ?? "";
		if (ct && !ALLOWED_CONTENT.some((re) => re.test(ct)))
			throw new Error(`Blocked content-type '${ct}'.`);
		return await readCapped(res);
	}
	throw new Error(`Too many redirects (> ${MAX_REDIRECTS}).`);
}
