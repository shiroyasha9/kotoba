// Polish judge through OpenRouter: one checklist per input (what a rewrite must keep), cached to disk, then one verdict
// per output against that fixed checklist (docs/research/polish.md, section 3).
// bun --env-file="$KOTOBA_ENV_FILE" polish/judge.ts --set dev|test --sample N --variants V,V|all [--concurrency N] [--dry-run]
// The briefs and JSON schemas live in <data>/judge/. Every call is appended to <data>/results/judge-raw.jsonl; the
// verdicts (results/judge-verdicts.jsonl) are rebuilt from that file after each run.

import { parseArgs } from "node:util";
import { fail, intArg } from "../cli.ts";
import { API, Budget, authHeaders, loggedCall, readJsonl, retryAfter, runCalls, spentUsd } from "../openrouter.ts";
import type { Verdict } from "./report.ts";
import { COST_CAP_USD, DEV_SIZE, type Pair, type PolishRow, loadPairs, rawFiles } from "./run.ts";
import { split, stratified } from "./score.ts";

/**
 * GPT-6 Luna at medium reasoning: cheap, structured outputs on its zero-data-retention endpoints (Azure), and not one of
 * the candidates, so no model grades its own rewrites. Its endpoints list `max_completion_tokens`, not `max_tokens`.
 * A pilot with Claude Haiku 5.5 (a candidate) "corrected" speech-to-text names in its own checklists; its rows stay in the
 * raw file for the cost, under their own `judge`.
 */
const JUDGE = { model: "openai/gpt-6-luna", reasoning: { effort: "medium" }, limit: { max_completion_tokens: 16000 } };
/** Dry-run estimate per call (USD), from the first judge rows. */
const PLANNED_USD = { checklist: 0.002, score: 0.002 };

type Checklist = { items: { id: string; kind: string; text: string; quote: string; critical: boolean }[] };
type Score = {
	items: { id: string; status: "kept" | "weakened" | "changed" | "lost"; evidence: string }[];
	added: { quote: string; why: string }[];
	answered: boolean;
	clarity: number;
};

export type JudgeRow = {
	kind: "checklist" | "score";
	/** The judge model; absent on the Haiku 5.5 pilot rows. */
	judge?: string;
	variant: string | null;
	id: string;
	attempt: number;
	status: number;
	ok: boolean;
	totalMs: number;
	text: string | null;
	usage: { prompt_tokens?: number; completion_tokens?: number; cost?: number; [k: string]: unknown } | null;
	cost: number | null;
	error?: string;
};

function call(
	sink: { out: string; budget: Budget },
	kind: JudgeRow["kind"],
	variant: string | null,
	id: string,
	brief: string,
	schema: unknown,
	stdin: string,
): Promise<JudgeRow> {
	const body = JSON.stringify({
		model: JUDGE.model,
		...JUDGE.limit,
		messages: [
			{ role: "system", content: brief },
			{ role: "user", content: `<stdin>\n${stdin}\n</stdin>` },
		],
		reasoning: JUDGE.reasoning,
		response_format: { type: "json_schema", json_schema: { name: kind, strict: true, schema } },
		provider: { zdr: true, require_parameters: true },
	});
	return loggedCall(sink, async (attempt) => {
		const t0 = performance.now();
		let status = 0;
		let error: string | undefined;
		let text: string | null = null;
		let usage: JudgeRow["usage"] = null;
		let retryAfterSec: number | null = null;
		try {
			const res = await fetch(`${API}/chat/completions`, { method: "POST", headers: authHeaders(), body, signal: AbortSignal.timeout(180_000) });
			status = res.status;
			retryAfterSec = retryAfter(res);
			const json = (await res.json()) as {
				choices?: { message?: { content?: string } }[];
				usage?: JudgeRow["usage"];
				error?: { message?: string };
			};
			usage = json.usage ?? null;
			text = json.choices?.[0]?.message?.content ?? null;
			if (!res.ok || json.error) error = json.error?.message ?? `HTTP ${res.status}`;
			else if (text) JSON.parse(text);
		} catch (e) {
			error = String(e);
			if (status === 200) status = 0;
		}
		const row: JudgeRow = {
			kind,
			judge: JUDGE.model,
			variant,
			id,
			attempt,
			status,
			ok: status === 200 && !error && !!text,
			totalMs: performance.now() - t0,
			text,
			usage,
			cost: usage?.cost ?? null,
			...(error ? { error } : {}),
		};
		return { row, retryAfterSec };
	});
}

/** First successful row of the current judge per key. */
function firstOk(rows: JudgeRow[], kind: JudgeRow["kind"]): Map<string, JudgeRow> {
	const out = new Map<string, JudgeRow>();
	for (const r of rows)
		if (r.kind === kind && r.ok && r.judge === JUDGE.model && !out.has(`${r.variant}\t${r.id}`)) out.set(`${r.variant}\t${r.id}`, r);
	return out;
}

/** Verdicts from the score rows; a status missing for a listed item counts as lost. */
export function verdicts(rows: JudgeRow[]): Verdict[] {
	const checklists = new Map([...firstOk(rows, "checklist").values()].map((r) => [r.id, JSON.parse(r.text!) as Checklist]));
	return [...firstOk(rows, "score").values()].flatMap((r) => {
		const checklist = checklists.get(r.id);
		if (!checklist) return [];
		const score = JSON.parse(r.text!) as Score;
		const status = new Map(score.items.map((i) => [i.id, i.status]));
		const of = (id: string) => status.get(id) ?? "lost";
		const gone = (id: string) => of(id) === "lost" || of(id) === "changed";
		const ids = checklist.items.map((i) => i.id);
		return [
			{
				variant: r.variant!,
				id: r.id,
				items: ids.length,
				kept: ids.filter((id) => of(id) === "kept").length,
				weakened: ids.filter((id) => of(id) === "weakened").length,
				lost: ids.filter(gone).length,
				lostCritical: checklist.items.filter((i) => i.critical && gone(i.id)).length,
				added: score.added.length,
				answered: score.answered,
				clarity: Math.min(5, Math.max(1, score.clarity)),
			},
		];
	});
}

if (import.meta.main) {
	const { values } = parseArgs({
		args: Bun.argv.slice(2),
		options: {
			set: { type: "string", default: "test" },
			sample: { type: "string" },
			variants: { type: "string", default: "all" },
			concurrency: { type: "string", default: "8" },
			"dry-run": { type: "boolean", default: false },
			data: { type: "string", default: Bun.env.KOTOBA_POLISH_DATA },
		},
	});
	const dataDir = values.data ?? fail("--data DIR or KOTOBA_POLISH_DATA is required");
	const judgeDir = `${dataDir}/judge`;
	const raw = `${dataDir}/results/judge-raw.jsonl`;
	const pairs = await loadPairs(dataDir);
	const { dev, test } = split(pairs, DEV_SIZE);
	const n = intArg(values, "sample", 1);
	// Dev inputs are already in hash order; the test sample keeps the input-length mix of the test set.
	const members = values.set === "dev" ? dev.slice(0, n) : values.set === "test" ? (n ? stratified(test, n) : test) : fail("--set dev|test");
	const outputs = (await readJsonl<PolishRow>(`${dataDir}/results/polish-raw.jsonl`)).filter((r) => r.ok && r.text && (r.pass ?? "quality") === "quality");
	const known = new Set(["wispr", ...outputs.map((r) => r.variant)]);
	const wanted = values.variants === "all" ? [...known] : values.variants!.split(",");
	for (const v of wanted) if (!known.has(v)) fail(`--variants: no rows for ${v}`);

	const rows = await readJsonl<JudgeRow>(raw);
	const checklists = firstOk(rows, "checklist");
	const scored = firstOk(rows, "score");
	const textOf = (variant: string, p: Pair) => (variant === "wispr" ? p.wispr : outputs.find((r) => r.variant === variant && r.id === p.id)?.text);
	const checklistJobs = members.filter((p) => !checklists.has(`null\t${p.id}`));
	const scoreJobs = members.flatMap((p) => wanted.filter((v) => textOf(v, p) && !scored.has(`${v}\t${p.id}`)).map((v) => ({ v, p })));
	const spent = await spentUsd(rawFiles(dataDir));
	console.log(
		`Judge plan: ${members.length} inputs (${values.set}) x ${wanted.length} variants; ${checklistJobs.length} checklists and ${scoreJobs.length} verdicts pending, estimate $${(checklistJobs.length * PLANNED_USD.checklist + scoreJobs.length * PLANNED_USD.score).toFixed(3)}; spent so far $${spent.toFixed(4)}; cap $${COST_CAP_USD}`,
	);
	if (!values["dry-run"]) {
		const budget = new Budget(COST_CAP_USD, spent);
		const sink = { out: raw, budget };
		const concurrency = intArg(values, "concurrency", 1) ?? 8;
		const brief = (name: string) => Bun.file(`${judgeDir}/${name}-brief.md`).text();
		const schema = (name: string) => Bun.file(`${judgeDir}/${name}.schema.json`).json();
		const [checklistBrief, checklistSchema, scoreBrief, scoreSchema] = await Promise.all([brief("checklist"), schema("checklist"), brief("score"), schema("score")]);
		await runCalls("checklist", checklistJobs, concurrency, budget, (p) => call(sink, "checklist", null, p.id, checklistBrief, checklistSchema, p.input), (p) => p.id);
		const ready = firstOk(await readJsonl<JudgeRow>(raw), "checklist");
		await runCalls(
			"score",
			scoreJobs.filter(({ p }) => ready.has(`null\t${p.id}`)),
			concurrency,
			budget,
			({ v, p }) => {
				const items = (JSON.parse(ready.get(`null\t${p.id}`)!.text!) as Checklist).items;
				const stdin = `<original>\n${p.input}\n</original>\n\n<checklist>\n${JSON.stringify(items)}\n</checklist>\n\n<rewrite>\n${textOf(v, p)}\n</rewrite>`;
				return call(sink, "score", v, p.id, scoreBrief, scoreSchema, stdin);
			},
			({ v, p }) => `${v} ${p.id}`,
		);
		console.log(`  spent $${budget.total.toFixed(4)}`);
	}
	const all = verdicts(await readJsonl<JudgeRow>(raw));
	await Bun.write(`${dataDir}/results/judge-verdicts.jsonl`, all.map((v) => JSON.stringify(v)).join("\n") + "\n");
	console.log(`  ${all.length} verdicts in results/judge-verdicts.jsonl`);
}
