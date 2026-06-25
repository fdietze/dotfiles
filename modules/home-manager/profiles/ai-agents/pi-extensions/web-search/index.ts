/**
 * web-search: two tools for the agent — `web_search` and `web_fetch`.
 *
 * Design (converged from a safety/innovation/cost debate):
 *  - ONE pluggable search backend, auto-detected from env (privacy-first:
 *    SearXNG > Tavily > Brave). No hardcoded default, no silent SaaS leak.
 *  - web_fetch turns a URL into clean markdown via Jina Reader, behind a
 *    hard SSRF guard (no localhost / private IPs / odd schemes).
 *  - Zero runtime npm deps: native fetch() + typebox (provided by pi).
 *  - Fail loud: no silent cross-backend cascade; errors name the cause.
 *
 * Config (env, all optional, auto-detected at load):
 *   PI_SEARX_URL   - self-hosted SearXNG base URL (private, $0)
 *   TAVILY_API_KEY - Tavily (ranked + synthesized answer)
 *   BRAVE_API_KEY  - Brave Search API (free 2k/mo)
 *
 * Edit in repo + home-manager switch, then `/reload` in pi (re-reads env).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { type Backend, detectBackend, NO_BACKEND_ERROR, type SearchResult } from "./backends.ts";
import { fetchAsMarkdown } from "./fetch.ts";

function renderResults(results: SearchResult[]): string {
	if (results.length === 0) return "No results.";
	return results
		.map((r, i) => `${i + 1}. ${r.title || "(untitled)"} — ${r.url}\n   ${r.snippet}`)
		.join("\n\n");
}

export default function (pi: ExtensionAPI) {
	const backend: Backend | null = detectBackend();

	const searchDesc = backend
		? `Search the web via ${backend.name}. ${
				backend.leaksExternally
					? "NOTE: queries are sent to a third-party service."
					: "Queries stay on your self-hosted instance (no external leak)."
			} Returns a ranked list of {title, url, snippet}.`
		: `Search the web. NOT CONFIGURED — calling this returns setup instructions. ${NO_BACKEND_ERROR.split("\n")[0]}`;

	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description: searchDesc,
		promptSnippet: "Search the web for current information (web_search), then read a page with web_fetch",
		promptGuidelines: [
			"Use web_search for current/external information you don't already know; then use web_fetch on a result URL to read the full page.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query" }),
			count: Type.Optional(
				Type.Integer({ minimum: 1, maximum: 10, default: 5, description: "Number of results (1-10)" }),
			),
		}),
		async execute(_id, params, signal) {
			if (!backend)
				return { content: [{ type: "text", text: NO_BACKEND_ERROR }], isError: true, details: {} };
			const count = params.count ?? 5;
			const { results, answer } = await backend.search(params.query, count, signal);
			const parts: string[] = [];
			if (answer) parts.push(`Answer: ${answer}\n`);
			parts.push(renderResults(results));
			return {
				content: [{ type: "text", text: parts.join("\n") }],
				details: { backend: backend.name, query: params.query, count, results, answer },
			};
		},
	});

	pi.registerTool({
		name: "web_fetch",
		label: "Web Fetch",
		description:
			"Fetch a web page and return its main content as clean markdown (via Jina Reader). " +
			"Refuses localhost / private addresses and non-http(s) URLs.",
		parameters: Type.Object({
			url: Type.String({ description: "Absolute http(s) URL to fetch" }),
		}),
		async execute(_id, params, signal) {
			const markdown = await fetchAsMarkdown(params.url, signal);
			return {
				content: [{ type: "text", text: markdown }],
				details: { url: params.url, bytes: markdown.length },
			};
		},
	});
}
