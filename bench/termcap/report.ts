// Builds results/report.md for the list-size bench from the raw JSONL files only.

import { BENCH_SEED, type Clip, type Paths, mulberry32 } from "../data.ts";
import { okRowsByVariant, readJsonl, sumCost } from "../openrouter.ts";
import { fmtUsd, ist, percentile, table } from "../report.ts";
import { termRecall, wer } from "../score.ts";
import type { SttRow } from "../stt.ts";
import { CONDITIONS, LATENCY_KEYS, type PoolTerm, REUSED, type TermcapPaths, countTerm, neededCoverage, wisprTime } from "./lists.ts";

type ReportInput = {
	bp: Paths;
	tp: TermcapPaths;
	clips: Clip[];
	refOf: (c: Clip) => string;
	/** Clips with the owner's hand-corrected reference. */
	owner: Set<string>;
	real: PoolTerm[];
	dictionary: PoolTerm[];
	lists: (condition: string, clipId: string) => string[];
	/** Lists built but not sent: scored for needed-term coverage only. */
	offline: string[];
	/** Requests in flight in the accuracy pass. */
	concurrency: number;
};

const pct = (num: number, den: number) => (den ? `${((100 * num) / den).toFixed(1)}%` : "-");
const ms = (v: number | null) => (v === null ? "-" : `${Math.round(v)}`);
const range = (lo: number | null, hi: number | null, sign = false) =>
	lo === null || hi === null ? "-" : `${sign && lo > 0 ? "+" : ""}${(100 * lo).toFixed(1)} to ${sign && hi > 0 ? "+" : ""}${(100 * hi).toFixed(1)}`;

type PerClip = { id: string; errors: number; words: number };

/** 95% percentile bootstrap over clips of corpus WER, or of the paired WER difference `a - b`. */
function bootstrap(a: PerClip[], b?: Map<string, PerClip>, rounds = 2000): [number | null, number | null] {
	const pairs = b ? a.filter((x) => b.has(x.id)) : a;
	if (!pairs.length) return [null, null];
	const rand = mulberry32(BENCH_SEED);
	const rates: number[] = [];
	for (let r = 0; r < rounds; r++) {
		let errors = 0;
		let words = 0;
		for (let i = 0; i < pairs.length; i++) {
			const x = pairs[Math.floor(rand() * pairs.length)]!;
			errors += x.errors - (b ? b.get(x.id)!.errors : 0);
			words += x.words;
		}
		if (words) rates.push(errors / words);
	}
	return [percentile(rates, 0.025), percentile(rates, 0.975)];
}

/** Occurrences of each needed term (dictionary term in the reference) found in the hypothesis. */
function termHits(ref: string, hyp: string, terms: string[]) {
	return terms.map((term) => {
		const want = countTerm(ref, term);
		const found = countTerm(hyp, term);
		return { term, want, got: Math.min(want, found), extra: Math.max(0, found - want) };
	});
}

export async function writeTermcapReport(input: ReportInput): Promise<string> {
	const { bp, tp, clips, refOf, owner, real, dictionary, lists, offline, concurrency } = input;
	const [benchRows, sttRows, latRows, routeRows] = await Promise.all([
		readJsonl<SttRow>(bp.sttRaw),
		readJsonl<SttRow>(tp.sttRaw),
		readJsonl<SttRow>(tp.latencyRaw),
		readJsonl<SttRow>(tp.routeRaw),
	]);
	const bench = okRowsByVariant(benchRows);
	const mine = okRowsByVariant(sttRows);
	const lat = okRowsByVariant(latRows);
	const keys = ["none", "bench-33", ...CONDITIONS.map((c) => c.key)];
	const rowsOf = (key: string) => (key in REUSED ? bench.get(REUSED[key as keyof typeof REUSED]) : mine.get(key)) ?? new Map<string, SttRow>();
	const realTerms = real.map((t) => t.term);
	const addedAt = new Map(real.map((t) => [t.term, t.addedAt]));
	const realLower = new Set(realTerms.map((t) => t.toLowerCase()));
	const distractors = dictionary.filter((t) => !t.real).map((t) => t.term);

	type Stats = {
		key: string;
		n: number;
		perClip: PerClip[];
		listSize: number;
		realInList: number;
		tech: { hits: number; total: number };
		inList: { got: number; want: number };
		leftOut: { got: number; want: number };
		/** Left-out occurrences of terms the owner had added by the clip's time (the rest came from later edits). */
		leftOutExisting: number;
		inserted: { inList: number; notInList: number };
		latency: number[];
		perTerm: Map<string, { got: number; want: number; leftOut: number }>;
	};
	const stats = keys.map((key): Stats => {
		const rows = rowsOf(key);
		const s: Stats = {
			key,
			n: 0,
			perClip: [],
			listSize: 0,
			realInList: 0,
			tech: { hits: 0, total: 0 },
			inList: { got: 0, want: 0 },
			leftOut: { got: 0, want: 0 },
			leftOutExisting: 0,
			inserted: { inList: 0, notInList: 0 },
			latency: [],
			perTerm: new Map(realTerms.map((t) => [t, { got: 0, want: 0, leftOut: 0 }])),
		};
		for (const c of clips) {
			const row = rows.get(c.id);
			if (!row?.text) continue;
			const ref = refOf(c);
			const list = lists(key, c.id);
			const carried = new Set(list.map((t) => t.toLowerCase()));
			const w = wer(ref, row.text);
			const t = termRecall(ref, row.text, realTerms);
			s.n++;
			s.perClip.push({ id: c.id, errors: w.errors, words: w.refWords });
			s.listSize += list.length;
			s.realInList += list.filter((x) => realLower.has(x.toLowerCase())).length;
			s.tech.hits += t.hits;
			s.tech.total += t.total;
			s.latency.push(row.latencyMs);
			for (const h of termHits(ref, row.text, realTerms)) {
				const bucket = carried.has(h.term.toLowerCase()) ? s.inList : s.leftOut;
				bucket.got += h.got;
				bucket.want += h.want;
				const pt = s.perTerm.get(h.term)!;
				pt.got += h.got;
				pt.want += h.want;
				if (!carried.has(h.term.toLowerCase())) {
					pt.leftOut += h.want;
					if ((addedAt.get(h.term) ?? 0) <= wisprTime(c.timestamp!)) s.leftOutExisting += h.want;
				}
			}
			for (const h of termHits(ref, row.text, distractors)) {
				if (carried.has(h.term.toLowerCase())) s.inserted.inList += h.extra;
				else s.inserted.notInList += h.extra;
			}
		}
		return s;
	});
	const byKey = new Map(stats.map((s) => [s.key, s]));
	const sent = stats.filter((s) => s.n);
	const base = new Map(byKey.get("app")!.perClip.map((x) => [x.id, x]));
	const none = new Map(byKey.get("none")!.perClip.map((x) => [x.id, x]));
	const rate = (xs: PerClip[]) => pct(xs.reduce((a, x) => a + x.errors, 0), xs.reduce((a, x) => a + x.words, 0));
	const sttCost = sumCost(sttRows);
	const latCost = sumCost(latRows);
	const out: string[] = [];

	out.push(
		"# List-size bench (kotoba-bench-v1, MAI-Transcribe-2 phraseList)",
		"",
		`Generated ${ist(new Date().toISOString())} IST from the raw JSONL files.`,
		"",
		"## Data",
		"",
		`- Clips: ${clips.length}; ${clips.filter((c) => owner.has(c.id)).length} have the owner's hand-corrected reference, which is used where it exists (else the bench reference).`,
		`- \`app\`: the ${real.length} terms kotoba sends today for this dictionary, built as the app builds them (\`appKeyterms\`: the Wispr import, then \`PersonalDictionary.keyterms\`). \`bench-33\` is kotoba-bench-v1's \`mai+phraseList\` (phrases and replacements, 33 terms) and \`none\` its \`mai\` (run 2026-10-15), reused.`,
		`- A ${dictionary.length}-term dictionary: today's terms, then ${distractors.length} distractors appended as later terms (kotoba appends new terms at the end). Distractors are public developer names and type names from kotoba's Swift sources that occur in no reference; they have no add date and no earlier use unless the owner's Wispr history has the word.`,
		"- `today-100`: what `PersonalDictionary.keyterms` sends for that dictionary (the first 100 in stored order). `all-300`: the whole dictionary, no cap.",
		"- `ranked-25`: per clip, the plan's rule (phase3-plan.md section 3) over the 300 terms at the clip's time: pinned, then added in the last 14 days, then `uses × 0.5^(days since last use / 30)` over the owner's earlier Wispr dictations (whole word, case-insensitive), then stored order. Only dictations before the clip count. `random-25`: a seeded random 25 of the 300 per clip (control).",
		`- Cost from this bench's raw files: accuracy ${fmtUsd(sttCost)}, latency ${fmtUsd(latCost)}, total ${fmtUsd(sttCost + latCost)}.`,
		"",
		"## Accuracy per list",
		"",
		`Needed terms: occurrences of dictionary terms in the reference (case-insensitive whole phrase). In-list recall: needed terms that were in the list and appear in the output. Left-out recall: needed terms the list did not carry. Inserted distractors: distractor words in the output beyond the reference (in the list / not in the list). Latency here is the contended accuracy pass (\`${concurrency}\` in flight for this run's rows), not for gates; the \`none\` and \`bench-33\` rows are from the kotoba-bench-v1 run.`,
		"",
		table(
			["list", "clips", "terms sent (dict)", "WER", "WER 95% CI", "ΔWER vs app (pts, 95% CI)", "WER owner refs", "tech-term recall", "in-list recall", "left-out recall", "left out, term existed then", "inserted distractors", "contended p50 ms"],
			sent.map((s) => [
				s.key,
				s.n,
				s.n ? `${(s.listSize / s.n).toFixed(0)} (${(s.realInList / s.n).toFixed(1)})` : "-",
				rate(s.perClip),
				range(...bootstrap(s.perClip)),
				s.key === "app" ? "-" : range(...bootstrap(s.perClip, base), true),
				rate(s.perClip.filter((x) => owner.has(x.id))),
				pct(s.tech.hits, s.tech.total),
				`${pct(s.inList.got, s.inList.want)} (${s.inList.got}/${s.inList.want})`,
				`${pct(s.leftOut.got, s.leftOut.want)} (${s.leftOut.got}/${s.leftOut.want})`,
				s.key === "none" ? "-" : s.leftOutExisting,
				`${s.inserted.inList} / ${s.inserted.notInList}`,
				ms(percentile(s.latency, 0.5)),
			]),
		),
		"",
		`ΔWER vs none (pts, 95% CI): ${sent
			.filter((s) => s.key !== "none")
			.map((s) => `${s.key} ${range(...bootstrap(s.perClip, none), true)}`)
			.join("; ")}.`,
		"",
	);

	// --- Latency ---
	const latByKey = LATENCY_KEYS.filter((key) => lat.has(key)).map((key) => {
		const rows = [...(lat.get(key)?.values() ?? [])];
		return { key, rows, ms: rows.map((r) => r.latencyMs) };
	});
	const noneLat = new Map([...(lat.get("none")?.values() ?? [])].map((r) => [r.clipId, r.latencyMs]));
	out.push(
		"## Latency per list size (sequential pass)",
		"",
		`One request at a time on the bench's ${Math.max(0, ...latByKey.map((l) => l.rows.length)) || "-"} seeded 10-20 s latency clips; the condition order rotates by one on each clip. Request start to response end, through OpenRouter.`,
		"",
		table(
			["list", "n", "p50 ms", "p90 ms", "median Δ vs none ms", "request KB (mean)"],
			latByKey.map(({ key, rows, ms: xs }) => [
				key,
				rows.length,
				ms(percentile(xs, 0.5)),
				ms(percentile(xs, 0.9)),
				key === "none" || !noneLat.size ? "-" : ms(percentile(rows.filter((r) => noneLat.has(r.clipId)).map((r) => r.latencyMs - noneLat.get(r.clipId)!), 0.5)),
				rows.length ? (rows.reduce((a, r) => a + r.bodyBytes, 0) / rows.length / 1024).toFixed(1) : "-",
			]),
		),
		"",
	);

	// --- Run-to-run noise ---
	const same = (a: Map<string, SttRow> | undefined, b: Map<string, SttRow> | undefined) => {
		let pairs = 0;
		let equal = 0;
		for (const [id, r] of a ?? []) {
			const o = b?.get(id);
			if (!o) continue;
			pairs++;
			if (r.text?.trim() === o.text?.trim()) equal++;
		}
		return `${equal}/${pairs}`;
	};
	out.push(
		"## Run-to-run noise",
		"",
		`Same request, same text: none ${same(lat.get("none"), bench.get(REUSED.none))} latency clips (today vs kotoba-bench-v1, 2026-10-15); ${LATENCY_KEYS.filter((k) => k !== "none")
			.map((k) => `${k} ${same(lat.get(k), mine.get(k))}`)
			.join(", ")} (latency pass vs accuracy pass, both today).`,
		"",
	);

	// --- Route limit and offline coverage ---
	const bisect = routeRows.filter((r) => r.variant.startsWith("route-first-"));
	const sizeOf = (r: SttRow) => Number(r.variant.split("-").at(-1));
	const accepted = bisect.filter((r) => r.ok).map(sizeOf);
	const rejected = bisect.filter((r) => r.status === 400).map(sizeOf);
	const last = routeRows.find((r) => r.variant === "route-last-100");
	const neededIn = (key: string) => {
		const { inList, want } = neededCoverage(clips, refOf, realTerms, (id) => lists(key, id));
		return `${inList}/${want}`;
	};
	out.push(
		"## Route limit",
		"",
		accepted.length && rejected.length
			? `OpenRouter -> MAI \`phraseList\`: largest list accepted ${Math.max(...accepted)} terms, smallest rejected ${Math.min(...rejected)} (status 400), by bisection over first-N lists of the 300-term dictionary on one ${bisect[0]!.audioSec.toFixed(1)} s clip. The last 100 terms alone: status ${last?.status ?? "-"}${last?.ok ? ", so the limit is the count, not a term" : ""}.`
			: "Not probed yet (`--only route`).",
		"",
		"## Needed-term coverage, offline",
		"",
		"Needed-term occurrences that a list carries (no API call; the lists are in lists.jsonl).",
		"",
		table(["list", "in list"], [...CONDITIONS.map((c) => c.key), ...offline].map((k) => [k, neededIn(k)])),
		"",
	);

	// --- Per term ---
	out.push(
		"## Needed terms, recall per list",
		"",
		"Cells: found/needed. A `*` marks a list that left the term out on at least one needed clip (left-out occurrences in brackets).",
		"",
		table(
			["term", ...sent.map((s) => s.key)],
			realTerms
				.filter((t) => byKey.get("none")!.perTerm.get(t)!.want > 0)
				.map((t) => [
					t,
					...sent.map((s) => {
						const pt = s.perTerm.get(t)!;
						return `${pt.got}/${pt.want}${pt.leftOut ? ` * (${pt.leftOut})` : ""}`;
					}),
				]),
		),
		"",
	);

	const md = `${out.join("\n")}\n`;
	await Bun.write(tp.report, md);
	return md;
}
