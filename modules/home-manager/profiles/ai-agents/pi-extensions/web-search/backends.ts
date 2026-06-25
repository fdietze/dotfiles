/**
 * Search backends for the web-search extension.
 *
 * ONE pluggable backend, auto-detected from env at load time (no hardcoded
 * default, no silent SaaS leak). Precedence is privacy-first:
 *   SearXNG (PI_SEARX_URL) > Tavily (TAVILY_API_KEY) > Brave (BRAVE_API_KEY)
 * If none is configured, detectBackend() returns null and the tool reports a
 * clear setup error naming all three options.
 *
 * Every backend normalizes to a uniform SearchResult[] so the tool layer stays
 * backend-agnostic (functional core: pure-ish mappers; the only side effect is
 * fetch).
 */

export interface SearchResult {
	title: string;
	url: string;
	snippet: string;
}

export interface SearchResponse {
	results: SearchResult[];
	/** Synthesized answer (Tavily only). Shown as a leading block when present. */
	answer?: string;
}

export interface Backend {
	/** Human-readable backend id, surfaced in the tool description. */
	name: string;
	/** Does this backend send queries to a third party outside the user's control? */
	leaksExternally: boolean;
	search(query: string, count: number, signal?: AbortSignal): Promise<SearchResponse>;
}

const UA = "pi-web-search/1.0";

function str(x: unknown): string {
	return typeof x === "string" ? x : "";
}

// --- SearXNG (self-hosted, private, $0) -----------------------------------
function searxBackend(baseUrl: string): Backend {
	const root = baseUrl.replace(/\/+$/, "");
	return {
		name: `SearXNG (${root})`,
		leaksExternally: false,
		async search(query, count, signal) {
			const u = new URL(`${root}/search`);
			u.searchParams.set("q", query);
			u.searchParams.set("format", "json");
			const res = await fetch(u, { headers: { "User-Agent": UA }, signal });
			if (!res.ok)
				throw new Error(
					`SearXNG ${res.status} ${res.statusText}. Is JSON format enabled (search.formats: [html, json]) and PI_SEARX_URL correct?`,
				);
			const data = (await res.json()) as { results?: Array<Record<string, unknown>> };
			const results = (data.results ?? []).slice(0, count).map((r) => ({
				title: str(r.title),
				url: str(r.url),
				snippet: str(r.content),
			}));
			return { results };
		},
	};
}

// --- Tavily (agentic, ranked + synthesized answer) ------------------------
function tavilyBackend(apiKey: string): Backend {
	return {
		name: "Tavily",
		leaksExternally: true,
		async search(query, count, signal) {
			const res = await fetch("https://api.tavily.com/search", {
				method: "POST",
				headers: { "Content-Type": "application/json", "User-Agent": UA },
				body: JSON.stringify({
					api_key: apiKey,
					query,
					max_results: count,
					include_answer: true,
					search_depth: "basic",
				}),
				signal,
			});
			if (!res.ok) {
				const body = await res.text().catch(() => "");
				throw new Error(`Tavily ${res.status} ${res.statusText}${body ? `: ${body.slice(0, 200)}` : ""}`);
			}
			const data = (await res.json()) as {
				answer?: string;
				results?: Array<Record<string, unknown>>;
			};
			const results = (data.results ?? []).slice(0, count).map((r) => ({
				title: str(r.title),
				url: str(r.url),
				snippet: str(r.content),
			}));
			return { results, answer: data.answer || undefined };
		},
	};
}

// --- Brave Search API (free 2k/mo, zero ops) ------------------------------
function braveBackend(apiKey: string): Backend {
	return {
		name: "Brave Search",
		leaksExternally: true,
		async search(query, count, signal) {
			const u = new URL("https://api.search.brave.com/res/v1/web/search");
			u.searchParams.set("q", query);
			u.searchParams.set("count", String(count));
			const res = await fetch(u, {
				headers: { Accept: "application/json", "X-Subscription-Token": apiKey, "User-Agent": UA },
				signal,
			});
			if (!res.ok) {
				const hint = res.status === 429 ? " (free quota 2k/mo likely exceeded)" : "";
				throw new Error(`Brave ${res.status} ${res.statusText}${hint}`);
			}
			const data = (await res.json()) as { web?: { results?: Array<Record<string, unknown>> } };
			const results = (data.web?.results ?? []).slice(0, count).map((r) => ({
				title: str(r.title),
				url: str(r.url),
				snippet: str(r.description),
			}));
			return { results };
		},
	};
}

/**
 * Auto-detect the active backend from env (privacy-first precedence).
 * Returns null when nothing is configured.
 */
export function detectBackend(env: NodeJS.ProcessEnv = process.env): Backend | null {
	const searx = env.PI_SEARX_URL?.trim();
	if (searx) return searxBackend(searx);
	const tavily = env.TAVILY_API_KEY?.trim();
	if (tavily) return tavilyBackend(tavily);
	const brave = env.BRAVE_API_KEY?.trim();
	if (brave) return braveBackend(brave);
	return null;
}

export const NO_BACKEND_ERROR =
	"No web-search backend configured. Set ONE of (privacy-first precedence):\n" +
	"  PI_SEARX_URL    - self-hosted SearXNG, e.g. http://127.0.0.1:8888 (private, $0)\n" +
	"  TAVILY_API_KEY  - Tavily (ranked + synthesized answer)\n" +
	"  BRAVE_API_KEY   - Brave Search API (free 2k/mo)";
