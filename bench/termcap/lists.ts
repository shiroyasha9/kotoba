// Term lists for the list-size bench: the list kotoba sends today, a 300-term
// dictionary (today's terms, then distractors added later), subsets ranked by
// the rule in phase3-plan.md section 3, and seeded random subsets as a control.

import { join } from "node:path";
import { mulberry32, shuffle } from "../data.ts";

export const DICTIONARY_SIZE = 300;
/** `PersonalDictionary.maxKeyterms` and `maxKeytermLength`. */
export const APP_CAP = 100;
const MAX_TERM_LENGTH = 50;
const DISTRACTOR_SEED = 20261016;
const RECENT_DAYS = 14;
const HALF_LIFE_DAYS = 30;
const DAY_MS = 86_400_000;

/**
 * Stand-ins for dictionary entries the owner does not say in these clips:
 * public developer names and identifier shapes, the kind of terms a large
 * dictionary or a context list carries. With the type names of kotoba's
 * Swift sources they fill the dictionary to 300; candidates that occur in
 * any reference are dropped first.
 */
export const DISTRACTOR_CANDIDATES = [
	"Tailwind", "Prisma", "Turborepo", "Kubernetes", "Terraform", "Grafana", "Sentry", "PostHog", "Clerk", "Resend",
	"Inngest", "Temporal", "Redis", "Upstash", "Neon", "PlanetScale", "Cloudflare", "Wrangler", "Hono", "tRPC",
	"Expo", "Zustand", "Jotai", "Vitest", "Playwright", "Storybook", "Biome", "ESLint", "Prettier", "pnpm",
	"Deno", "SwiftUI", "AppKit", "Xcode", "Sparkle", "Homebrew", "Ghostty", "Raycast", "Figma", "LangChain",
	"LlamaIndex", "pgvector", "Qdrant", "Pinecone", "Weaviate", "Mistral", "Ollama", "vLLM", "Groq", "Cerebras",
	"Deepgram", "ElevenLabs", "AssemblyAI", "Svelte", "SolidJS", "Astro", "Remix", "Nuxt", "Vite", "esbuild",
	"Rollup", "webpack", "Kysely", "Sequelize", "MongoDB", "DynamoDB", "Firestore", "ClickHouse", "Kafka", "RabbitMQ",
	"gRPC", "GraphQL", "Contentful", "Strapi", "Stripe", "Twilio", "SendGrid", "Algolia", "Meilisearch", "Typesense",
	"Elasticsearch", "Datadog", "Honeycomb", "Netlify", "Heroku", "DigitalOcean", "Hetzner", "Tauri", "Electron", "Flutter",
	"Kotlin", "Gradle", "CocoaPods", "SwiftData", "CoreML", "useEffect", "useMemo", "getServerSideProps", "tsconfig.json", "package.json",
	".env.local", "--dry-run", "user_id", "createdAt", "middleware.ts", "docker-compose.yml", "Dockerfile", "README.md", "AppDelegate", "URLSession",
	"NSPasteboard", "CGEventTap", "AVAudioEngine",
];

/** Wispr's `2026-10-01 12:00:47.050 +00:00` as ms since epoch. */
export const wisprTime = (ts: string) => new Date(ts.replace(" +00:00", "Z").replace(" ", "T")).getTime();

/** A dictionary entry; `addedAt` is ms since epoch (null: unknown, never counts as recent). */
export type PoolTerm = { term: string; addedAt: number | null; pinned: boolean; real: boolean };

/** A live row of Wispr's `Dictionary`, in row order. */
export type WisprRow = {
	phrase: string;
	replacement: string | null;
	createdAt: string;
	isDeleted: number;
	isStarred: number;
	isSnippet: number;
	source: string | null;
	observedSource: string | null;
};

const blank = (s: string | null | undefined) => !s?.trim();

/**
 * What kotoba sends after the Wispr import, built as the app builds it:
 * `WisprFlowImport.read` makes a phrase alone a term and a phrase with a
 * replacement a rule (a learned correction is both); `PersonalDictionary.keyterms`
 * sends the terms, then each rule's spelling, trimmed, without case-insensitive
 * duplicates, at most 50 characters each and `limit` in all.
 */
export function appKeyterms(rows: WisprRow[], limit = APP_CAP): string[] {
	const terms: string[] = [];
	const spellings: string[] = [];
	for (const r of rows) {
		if (r.isDeleted || r.isSnippet || blank(r.phrase)) continue;
		if (!blank(r.replacement)) spellings.push(r.replacement!);
		else {
			terms.push(r.phrase);
			if (r.source === "user_edits" && !blank(r.observedSource) && r.observedSource!.toLowerCase() !== r.phrase.toLowerCase()) {
				spellings.push(r.phrase);
			}
		}
	}
	return firstKeyterms([...terms, ...spellings], limit);
}

/** `PersonalDictionary.keyterms` over terms in stored order. */
export function firstKeyterms(terms: string[], limit: number): string[] {
	const seen = new Set<string>();
	const out: string[] = [];
	for (const t of terms) {
		const trimmed = t.trim();
		if (!trimmed || trimmed.length > MAX_TERM_LENGTH || seen.has(trimmed.toLowerCase())) continue;
		seen.add(trimmed.toLowerCase());
		out.push(trimmed);
		if (out.length === limit) break;
	}
	return out;
}

/**
 * The owner's terms, then distractors up to `size` in a seeded order: kotoba
 * appends new terms at the end, so these stand for words added later. They
 * carry no add date, so the recency tier never holds them.
 */
export function buildDictionary(real: PoolTerm[], distractors: string[], size = DICTIONARY_SIZE): PoolTerm[] {
	const fill = shuffle(distractors, mulberry32(DISTRACTOR_SEED))
		.slice(0, Math.max(0, size - real.length))
		.map((term): PoolTerm => ({ term, addedAt: null, pinned: false, real: false }));
	return [...real, ...fill];
}

/** Earlier dictations that contain a term: their times in ms, ascending. */
export type UseTimes = Map<string, number[]>;

const boundaries = new Map<string, RegExp>();
/** Cached: `match` with the `g` flag starts from 0 on every call, so one RegExp per term is safe. */
function boundary(term: string): RegExp {
	let re = boundaries.get(term);
	if (!re) {
		re = new RegExp(`(?<![\\p{L}\\p{N}_])${RegExp.escape(term.trim())}(?![\\p{L}\\p{N}_])`, "giu");
		boundaries.set(term, re);
	}
	return re;
}

/** Whole-phrase, case-insensitive occurrences of `term`; `zod` does not match `zodiac`. */
export function countTerm(text: string, term: string): number {
	return text.match(boundary(term))?.length ?? 0;
}

/** Needed-term occurrences (today's terms in each clip's reference) and how many of them the clip's list carries. */
export function neededCoverage<C extends { id: string }>(
	clips: C[],
	refOf: (c: C) => string,
	terms: string[],
	listOf: (clipId: string) => string[],
): { inList: number; want: number } {
	let inList = 0;
	let want = 0;
	for (const c of clips) {
		const list = new Set(listOf(c.id).map((t) => t.toLowerCase()));
		for (const t of terms) {
			const n = countTerm(refOf(c), t);
			want += n;
			if (list.has(t.toLowerCase())) inList += n;
		}
	}
	return { inList, want };
}

/** For each term, the times of the dictations in `history` that contain it. */
export function useTimes(terms: string[], history: { at: number; text: string }[]): UseTimes {
	const sorted = [...history].sort((a, b) => a.at - b.at);
	return new Map(terms.map((t) => [t, sorted.filter((d) => countTerm(d.text, t) > 0).map((d) => d.at)]));
}

/** `uses × 0.5^(age in days / 30)` over dictations strictly before `now`; 0 without use. */
export function useScore(times: number[] | undefined, now: number): number {
	const before = (times ?? []).filter((t) => t < now);
	if (!before.length) return 0;
	const ageDays = (now - before.at(-1)!) / DAY_MS;
	return before.length * 0.5 ** (ageDays / HALF_LIFE_DAYS);
}

/**
 * The plan's rule (phase3-plan.md section 3): pinned terms, then terms added in
 * the last 14 days, then terms by use score, then the rest; ties keep stored order.
 * `useFirst` swaps the two middle tiers (scored here offline only).
 */
export function rankedTerms(pool: PoolTerm[], uses: UseTimes, now: number, limit: number, useFirst = false): string[] {
	const tier = (t: PoolTerm, score: number) => {
		if (t.pinned) return 0;
		const recent = t.addedAt !== null && t.addedAt <= now && now - t.addedAt <= RECENT_DAYS * DAY_MS;
		if (useFirst ? score > 0 : recent) return 1;
		return (useFirst ? recent : score > 0) ? 2 : 3;
	};
	return pool
		.map((t, i) => {
			const score = useScore(uses.get(t.term), now);
			return { t, i, score, tier: tier(t, score) };
		})
		.sort((a, b) => a.tier - b.tier || b.score - a.score || a.i - b.i)
		.slice(0, limit)
		.map((x) => x.t.term);
}

/** FNV-1a, so each clip gets its own random subset that a rerun reproduces. */
export function seedOf(text: string): number {
	let h = 0x811c9dc5;
	for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193);
	return h >>> 0;
}

export function randomTerms(pool: PoolTerm[], limit: number, seed: number): string[] {
	return shuffle(pool, mulberry32(seed))
		.slice(0, limit)
		.map((t) => t.term);
}

export type Condition = { key: string; size: number; pick: "app" | "first" | "random" | "ranked"; useFirst?: boolean };

/** New conditions, sent as Azure `phraseList.phrases`. Ranked and random lists come from the 300-term dictionary. */
export const CONDITIONS = [
	{ key: "app", size: APP_CAP, pick: "app" },
	{ key: "ranked-25", size: 25, pick: "ranked" },
	{ key: "random-25", size: 25, pick: "random" },
	{ key: "today-100", size: APP_CAP, pick: "first" },
	{ key: "all-300", size: DICTIONARY_SIZE, pick: "first" },
] as const satisfies readonly Condition[];
/** Reused from kotoba-bench-v1's stt-raw.jsonl: no list, and the bench's own list (phrases and replacements, 33 terms). */
export const REUSED = { none: "mai", "bench-33": "mai+phraseList" } as const;
/** Sequential latency pass on the bench's 40 latency clips. */
export const LATENCY_KEYS = ["none", "ranked-25", "app", "today-100", "all-300"] as const;

export type ListRow = { clipId: string; condition: string; terms: string[] };

export function termcapPaths(out: string) {
	const results = join(out, "results");
	const sttRaw = join(results, "stt-raw.jsonl");
	const latencyRaw = join(results, "latency-raw.jsonl");
	/** One-off calls that find the route's phrase-list limit. */
	const routeRaw = join(results, "route-raw.jsonl");
	return {
		out,
		wisprDictionary: join(out, "data", "wispr-dictionary.json"),
		wisprHistory: join(out, "data", "wispr-history.json"),
		/** Frozen at the first run, so later runs send the same lists. */
		distractors: join(out, "data", "distractors.json"),
		dictionary: join(out, "dictionary-300.json"),
		lists: join(out, "lists.jsonl"),
		sttRaw,
		latencyRaw,
		routeRaw,
		rawFiles: [sttRaw, latencyRaw, routeRaw],
		report: join(results, "report.md"),
	};
}
export type TermcapPaths = ReturnType<typeof termcapPaths>;
