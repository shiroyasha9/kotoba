// Polish report: per variant, from the raw JSONL and the judge verdicts only. It holds aggregates, no text.

import { readJsonl } from "../openrouter.ts";
import type { Pair, PolishRow } from "./run.ts";
import { badChars, codeTokens, missingTokens, newTokens, percentile, wordCount } from "./score.ts";

/** One judge verdict on one output (judge.ts writes them); `variant` "wispr" is Wispr Flow's own output. */
export type Verdict = {
	variant: string;
	id: string;
	items: number;
	kept: number;
	weakened: number;
	/** Lost or changed. */
	lost: number;
	/** Lost or changed items the checklist marks critical. */
	lostCritical: number;
	added: number;
	answered: boolean;
	clarity: number;
};

type Line = { variant: string; set: string; cells: (string | number)[] };

const pct = (n: number, d: number) => (d ? `${((100 * n) / d).toFixed(1)}%` : "-");
const fmt = (n: number, digits = 0) => (Number.isFinite(n) ? n.toFixed(digits) : "-");
const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : Number.NaN);

/** The first successful row per (variant, id). */
function firstOk(rows: PolishRow[]): Map<string, Map<string, PolishRow>> {
	const out = new Map<string, Map<string, PolishRow>>();
	for (const r of rows) {
		if (!r.ok || r.text == null) continue;
		const byId = out.get(r.variant) ?? new Map<string, PolishRow>();
		if (!byId.has(r.id)) byId.set(r.id, r);
		out.set(r.variant, byId);
	}
	return out;
}

export async function writeReport(dataDir: string, pairs: Pair[], sets: { dev: Pair[]; test: Pair[] }): Promise<void> {
	const rows = await readJsonl<PolishRow>(`${dataDir}/results/polish-raw.jsonl`);
	const verdicts = await readJsonl<Verdict>(`${dataDir}/results/judge-verdicts.jsonl`);
	const verdictOf = new Map(verdicts.map((v) => [`${v.variant}\t${v.id}`, v]));
	const byVariant = firstOk(rows.filter((r) => (r.pass ?? "quality") === "quality"));
	// The latency pass (one request at a time) gives the latency columns where it ran; else the quality pass does.
	const latency = rows.filter((r) => r.ok && r.pass === "latency");
	const failures = new Map<string, number>();
	for (const r of rows) if (!r.ok) failures.set(r.variant, (failures.get(r.variant) ?? 0) + 1);
	const byId = new Map(pairs.map((p) => [p.id, p]));
	const lines: Line[] = [];

	const summarize = (variant: string, set: string, members: Pair[], outputOf: (p: Pair) => { text: string; row?: PolishRow } | undefined) => {
		const outs = members.flatMap((p) => {
			const o = outputOf(p);
			return o ? [{ p, ...o }] : [];
		});
		if (!outs.length) return;
		let tokens = 0;
		let missing = 0;
		let rowsMissing = 0;
		let added = 0;
		let rowsBad = 0;
		const ratios: number[] = [];
		for (const { p, text } of outs) {
			const m = missingTokens(p.input, text);
			tokens += codeTokens(p.input).length;
			missing += m.length;
			if (m.length) rowsMissing++;
			added += newTokens(p.input, text).length;
			if (badChars(text)) rowsBad++;
			ratios.push(wordCount(text) / p.inWords);
		}
		const ids = new Set(members.map((p) => p.id));
		const sequential = latency.filter((r) => r.variant === variant && ids.has(r.id));
		const timed = sequential.length ? sequential : outs.flatMap(({ row }) => (row ? [row] : []));
		const mid = timed.filter((r) => {
			const w = byId.get(r.id)!.inWords;
			return w >= 200 && w <= 400;
		});
		const vs = outs.flatMap(({ p }) => {
			const v = verdictOf.get(`${variant}\t${p.id}`);
			return v ? [v] : [];
		});
		const items = vs.reduce((s, v) => s + v.items, 0);
		lines.push({
			variant,
			set,
			cells: [
				outs.length,
				failures.get(variant) ?? 0,
				vs.length ? pct(vs.reduce((s, v) => s + v.kept, 0), items) : "-",
				vs.length ? pct(vs.filter((v) => v.lost > 0).length, vs.length) : "-",
				vs.length ? fmt(mean(vs.map((v) => v.lost)), 2) : "-",
				vs.length ? pct(vs.filter((v) => v.lostCritical > 0).length, vs.length) : "-",
				vs.length ? pct(vs.reduce((s, v) => s + v.weakened, 0), items) : "-",
				vs.length ? pct(vs.filter((v) => v.added > 0).length, vs.length) : "-",
				vs.length ? vs.filter((v) => v.answered).length : "-",
				vs.length ? fmt(mean(vs.map((v) => v.clarity)), 2) : "-",
				pct(tokens - missing, tokens),
				pct(rowsMissing, outs.length),
				fmt(added / outs.length, 2),
				pct(rowsBad, outs.length),
				fmt(percentile(ratios, 50), 2),
				timed.length ? fmt(percentile(timed.map((r) => r.ttftMs ?? Number.NaN), 50)) : "-",
				timed.length ? fmt(percentile(timed.map((r) => r.totalMs), 50)) : "-",
				timed.length ? fmt(percentile(timed.map((r) => r.totalMs), 90)) : "-",
				mid.length ? `${fmt(percentile(mid.map((r) => r.totalMs), 50))} (${mid.length}${sequential.length ? " s" : ""})` : "-",
				timed.length ? fmt(mean(timed.map((r) => (r.cost ?? 0) * 1000)), 3) : "-",
			],
		});
	};

	for (const [set, members] of [
		["dev", sets.dev],
		["test", sets.test],
	] as const) {
		summarize("wispr", set, members, (p) => ({ text: p.wispr }));
		for (const [variant, outputs] of [...byVariant].sort(([a], [b]) => a.localeCompare(b))) {
			summarize(variant, set, members, (p) => {
				const row = outputs.get(p.id);
				return row ? { text: row.text!, row } : undefined;
			});
		}
	}

	const head = [
		"variant",
		"set",
		"n",
		"failed attempts (all retried)",
		"judge: items kept",
		"rows with a lost item",
		"lost items / row",
		"rows with a lost critical item",
		"items weakened",
		"rows with added content",
		"answered",
		"clarity 1-5",
		"code tokens kept",
		"rows missing a token",
		"new tokens / row",
		"rows with non-ASCII hyphen or space",
		"word ratio p50",
		"TTFT p50 ms",
		"total p50 ms",
		"total p90 ms",
		"total p50 ms, 200-400 words (n; sequential when marked s)",
		"USD per 1,000 Polish",
	];
	const spent = rows.reduce((s, r) => s + (r.cost ?? 0), 0);
	const md = [
		"# Polish bench report",
		"",
		`Generated ${new Date().toISOString()} from results/polish-raw.jsonl (${rows.length} rows, $${spent.toFixed(4)}) and results/judge-verdicts.jsonl (${verdicts.length} verdicts).`,
		"",
		`| ${head.join(" | ")} |`,
		`| ${head.map(() => "---").join(" | ")} |`,
		...lines.map((l) => `| ${[l.variant, l.set, ...l.cells].join(" | ")} |`),
		"",
	].join("\n");
	await Bun.write(`${dataDir}/results/report.md`, md);
	console.log(md);
}
