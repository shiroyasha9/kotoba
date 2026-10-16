// Polish bench: the owner's Wispr Flow Polish inputs through candidate models and prompts (docs/research/polish.md).
// bun --env-file="$KOTOBA_ENV_FILE" polish/run.ts [--only gen|report] [--set dev|test|all] [--sample N] [--pass quality|latency] [--models KEY,KEY] [--versions N,N] [--limit N] [--concurrency N] [--cap USD] [--dry-run] [--data DIR]
// Data (outside git): <data>/data/polish-pairs.json, an export of Wispr's Polish table (query in polish.md). Every call
// is appended to <data>/results/polish-raw.jsonl as it completes; the report and the cap read that file only.

import { parseArgs } from "node:util";
import { fail, intArg } from "../cli.ts";
import { API, Budget, authHeaders, loggedCall, readJsonl, retryAfter, runCalls, spentUsd } from "../openrouter.ts";
import { POLISH_PROMPTS, userMessage } from "./prompts.ts";
import { writeReport } from "./report.ts";
import { htmlToText, split, stratified, wordCount } from "./score.ts";

/** Hard stop over every raw file of this bench (generation and any paid judge), across runs. */
export const COST_CAP_USD = 3;
/** Inputs that pick the prompt; the rest are the test set. */
export const DEV_SIZE = 25;
/** Test inputs that were generated and judged (inside the USD cap): an equal share per input-length quartile. */
export const TEST_SAMPLE = 40;

/** Every raw file that books spend against the cap: generation and the paid judge. */
export const rawFiles = (dataDir: string) => [`${dataDir}/results/polish-raw.jsonl`, `${dataDir}/results/judge-raw.jsonl`];

export type PolishModel = {
	key: string;
	model: string;
	provider: { zdr: true; only?: string[]; allow_fallbacks?: boolean };
	extra: Record<string, unknown>;
	/** Dry-run estimate, USD per 1M tokens in / out (zero-data-retention endpoint, GET /endpoints/zdr 2026-10-17). */
	price: [number, number];
	/** Reasoning tokens to expect per call in the dry run. */
	reasoning?: number;
};

export const POLISH_MODELS: PolishModel[] = [
	{
		key: "gemini-3.5-flash-lite",
		model: "google/gemini-3.5-flash-lite",
		provider: { zdr: true },
		// "minimal" is the lowest effort; the model ignores a custom temperature.
		extra: { reasoning: { effort: "minimal" } },
		price: [0.3, 2.5],
	},
	{
		key: "qwen3.8-27b@cerebras",
		model: "qwen/qwen3.8-27b",
		provider: { zdr: true, only: ["cerebras"], allow_fallbacks: false },
		extra: { reasoning: { enabled: false }, temperature: 0 },
		price: [0.99, 1.49],
	},
	{
		// Wispr Flow's own Polish model (Polish.usedProvider). Reasoning cannot be turned off; "low" is the lowest.
		key: "gpt-oss-120b@cerebras",
		model: "openai/gpt-oss-120b",
		provider: { zdr: true, only: ["cerebras"], allow_fallbacks: false },
		extra: { reasoning: { effort: "low" } },
		price: [0.35, 0.75],
		reasoning: 200,
	},
	{
		key: "claude-haiku-5.5",
		model: "anthropic/claude-haiku-5.5",
		provider: { zdr: true },
		extra: { reasoning: { enabled: false } },
		price: [0.1, 0.5],
	},
	{
		key: "deepseek-v4.1-flash",
		model: "deepseek/deepseek-v4.1-flash",
		provider: { zdr: true },
		extra: { reasoning: { effort: "none" }, temperature: 0 },
		price: [0.3, 1.2],
	},
	{
		// Unpinned, DeepSeek went to 11 hosts with total p50 1.0-8.6 s per host; Together was among the fastest (2026-10-17).
		key: "deepseek-v4.1-flash@together",
		model: "deepseek/deepseek-v4.1-flash",
		provider: { zdr: true, only: ["together"], allow_fallbacks: false },
		extra: { reasoning: { effort: "none" }, temperature: 0 },
		price: [0.3, 1.2],
	},
	{
		// Reasoning is mandatory; "low" is the lowest effort (GET /models, 2026-10-17).
		key: "gemini-3.8-flash",
		model: "google/gemini-3.8-flash",
		provider: { zdr: true },
		extra: { reasoning: { effort: "low" } },
		price: [0.825, 4.125],
	},
	{
		// Reasoning is mandatory on every endpoint ("cannot be disabled", 400 on 2026-10-17); "low" is the lowest effort.
		key: "claude-sonnet-5.5",
		model: "anthropic/claude-sonnet-5.5",
		provider: { zdr: true },
		extra: { reasoning: { effort: "low" } },
		price: [2.2, 11],
		reasoning: 300,
	},
];

export type Pair = { id: string; app: string; input: string; wispr: string; inWords: number; wisprWords: number; wisprMs: number; wisprModel: string };

export type PolishRow = {
	kind: "polish";
	variant: string;
	model: string;
	version: number;
	/** "quality" (concurrent) or "latency" (one request at a time, mid-length inputs); absent on early rows = quality. */
	pass?: Pass;
	id: string;
	attempt: number;
	startedAt: string;
	status: number;
	ok: boolean;
	/** Request start to first delta of any kind (content or reasoning). */
	firstChunkMs: number | null;
	/** Request start to first content delta. */
	ttftMs: number | null;
	totalMs: number;
	text: string | null;
	provider: string | null;
	usage: { prompt_tokens?: number; completion_tokens?: number; cost?: number; [k: string]: unknown } | null;
	cost: number | null;
	finishReason: string | null;
	error?: string;
};

export const variantKey = (model: string, version: number) => `${model}+polish-v${version}`;

export async function loadPairs(dataDir: string): Promise<Pair[]> {
	type Raw = { id: string; app: string; input: string; wispr: string; wisprMs: number; wisprModel: string };
	const raw = (await Bun.file(`${dataDir}/data/polish-pairs.json`).json()) as Raw[];
	return raw.map((r) => {
		const input = htmlToText(r.input);
		const wispr = htmlToText(r.wispr);
		return { ...r, input, wispr, inWords: wordCount(input), wisprWords: wordCount(wispr) };
	});
}

export type Pass = "quality" | "latency";
type Job = { m: PolishModel; version: number; pair: Pair; pass: Pass };
type Chunk = {
	provider?: string;
	usage?: PolishRow["usage"];
	error?: { code?: number | string; message?: string };
	choices?: { delta?: { content?: string; reasoning?: string }; finish_reason?: string | null }[];
};

function polish(sink: { out: string; budget: Budget }, { m, version, pair, pass }: Job): Promise<PolishRow> {
	const body = JSON.stringify({
		model: m.model,
		stream: true,
		max_tokens: 4096,
		messages: [
			{ role: "system", content: POLISH_PROMPTS[version] },
			{ role: "user", content: userMessage(pair.input, version) },
		],
		provider: m.provider,
		...m.extra,
	});
	return loggedCall(sink, async (attempt) => {
		const startedAt = new Date().toISOString();
		const t0 = performance.now();
		let status = 0;
		let error: string | undefined;
		let firstChunkMs: number | null = null;
		let ttftMs: number | null = null;
		let text = "";
		let provider: string | null = null;
		let usage: PolishRow["usage"] = null;
		let finishReason: string | null = null;
		let retryAfterSec: number | null = null;
		try {
			const res = await fetch(`${API}/chat/completions`, {
				method: "POST",
				headers: authHeaders(),
				body,
				signal: AbortSignal.timeout(90_000),
			});
			status = res.status;
			retryAfterSec = retryAfter(res);
			if (!res.ok || !res.body) {
				error = (await res.text()).slice(0, 500);
			} else {
				let buffer = "";
				read: for await (const part of res.body.pipeThrough(new TextDecoderStream())) {
					buffer += part;
					let nl = buffer.indexOf("\n");
					while (nl >= 0) {
						const line = buffer.slice(0, nl).trim();
						buffer = buffer.slice(nl + 1);
						nl = buffer.indexOf("\n");
						// Skip blank lines and SSE comments such as ": OPENROUTER PROCESSING".
						if (!line.startsWith("data:")) continue;
						const data = line.slice(5).trim();
						if (data === "[DONE]") break read;
						const c = JSON.parse(data) as Chunk;
						provider ??= c.provider ?? null;
						if (c.usage) usage = c.usage;
						if (c.error) {
							status = Number(c.error.code) || 500;
							error = c.error.message ?? JSON.stringify(c.error);
							break read;
						}
						const choice = c.choices?.[0];
						if (choice?.finish_reason) finishReason = choice.finish_reason;
						const delta = choice?.delta;
						if (firstChunkMs === null && (delta?.content || delta?.reasoning)) firstChunkMs = performance.now() - t0;
						if (delta?.content) {
							ttftMs ??= performance.now() - t0;
							text += delta.content;
						}
					}
				}
			}
		} catch (e) {
			error = String(e);
			if (status === 200) status = 0;
		}
		const row: PolishRow = {
			kind: "polish",
			variant: variantKey(m.key, version),
			model: m.model,
			version,
			pass,
			id: pair.id,
			attempt,
			startedAt,
			status,
			ok: status === 200 && !error && text.trim() !== "",
			firstChunkMs,
			ttftMs,
			totalMs: performance.now() - t0,
			text: text ? text.trim() : null,
			provider,
			usage,
			cost: usage?.cost ?? null,
			finishReason,
			...(error ? { error } : {}),
		};
		return { row, retryAfterSec };
	});
}

/** Dry-run estimate of one call: system prompt and input at ~1.35 tokens per word, output at the Wispr ratio. */
function plannedUsd({ m, version, pair }: Job): number {
	const promptTokens = POLISH_PROMPTS[version]!.split(/\s+/).length * 1.35 + pair.inWords * 1.35;
	const outTokens = pair.inWords * 0.7 * 1.35 + (m.reasoning ?? 0);
	return (promptTokens * m.price[0] + outTokens * m.price[1]) / 1e6;
}

if (import.meta.main) {
	const { values } = parseArgs({
		args: Bun.argv.slice(2),
		options: {
			only: { type: "string" },
			set: { type: "string", default: "dev" },
			// "latency": one request at a time on the set's 200-400 word inputs, in a fresh variant order per input.
			pass: { type: "string", default: "quality" },
			// The test set only: N inputs, an equal share from each input-length quartile (the judge uses the same N).
			sample: { type: "string" },
			models: { type: "string" },
			versions: { type: "string", default: "2" },
			limit: { type: "string" },
			concurrency: { type: "string", default: "4" },
			cap: { type: "string" },
			"dry-run": { type: "boolean", default: false },
			data: { type: "string", default: Bun.env.KOTOBA_POLISH_DATA },
		},
	});
	const dataDir = values.data ?? fail("--data DIR or KOTOBA_POLISH_DATA is required");
	const raw = `${dataDir}/results/polish-raw.jsonl`;
	const pairs = await loadPairs(dataDir);
	const { dev, test } = split(pairs, DEV_SIZE);

	if (values.only !== "report") {
		const sample = intArg(values, "sample", 1);
		const set =
			values.set === "dev" ? dev : values.set === "test" ? (sample ? stratified(test, sample) : test) : values.set === "all" ? pairs : fail("--set dev|test|all");
		const limit = intArg(values, "limit", 1);
		const pass = values.pass === "latency" || values.pass === "quality" ? (values.pass as Pass) : fail("--pass quality|latency");
		const pool = pass === "latency" ? set.filter((p) => p.inWords >= 200 && p.inWords <= 400) : set;
		const targets = limit ? pool.slice(0, limit) : pool;
		const models = values.models
			? values.models.split(",").map((k) => POLISH_MODELS.find((m) => m.key === k) ?? fail(`--models: unknown ${k}`))
			: POLISH_MODELS;
		const versions = values.versions!.split(",").map((v) => (POLISH_PROMPTS[Number(v)] ? Number(v) : fail(`--versions: unknown ${v}`)));
		const key = (variant: string, id: string, p: Pass) => `${variant}\t${id}\t${p}`;
		const done = new Set((await readJsonl<PolishRow>(raw)).filter((r) => r.ok).map((r) => key(r.variant, r.id, r.pass ?? "quality")));
		// Models interleaved per input, so a slow minute on the network hits every model alike.
		const queue = targets.flatMap((pair) =>
			versions.flatMap((version) =>
				(pass === "latency" && targets.indexOf(pair) % 2 ? [...models].reverse() : models)
					.filter((m) => !done.has(key(variantKey(m.key, version), pair.id, pass)))
					.map((m) => ({ m, version, pair, pass })),
			),
		);
		const spent = await spentUsd(rawFiles(dataDir));
		const planned = queue.reduce((s, j) => s + plannedUsd(j), 0);
		const perModel = models.map((m) => `${m.key} $${queue.filter((j) => j.m === m).reduce((s, j) => s + plannedUsd(j), 0).toFixed(3)}`);
		console.log(`Polish plan: ${targets.length} inputs (${values.set}) x ${models.length} models x ${versions.length} versions; ${queue.length} calls pending`);
		console.log(`  estimate $${planned.toFixed(3)} (${perModel.join(", ")}); spent so far $${spent.toFixed(4)}; cap $${COST_CAP_USD}`);
		if (!values["dry-run"] && queue.length) {
			const extra = values.cap === undefined ? undefined : Number(values.cap);
			const cap = Math.min(COST_CAP_USD, extra === undefined ? COST_CAP_USD : spent + extra);
			const budget = new Budget(cap, spent);
			const concurrency = pass === "latency" ? 1 : (intArg(values, "concurrency", 1) ?? 4);
			await runCalls("polish", queue, concurrency, budget, (job) => polish({ out: raw, budget }, job), (j) => `${j.m.key} ${j.pair.id}`);
			console.log(`  spent $${budget.total.toFixed(4)}`);
		}
	}
	// The test stage ran on the stratified sample the judge uses, so the report's test rows are that sample.
	if (values.only !== "gen") await writeReport(dataDir, pairs, { dev, test: stratified(test, TEST_SAMPLE) });
}
