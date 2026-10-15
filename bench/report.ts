// Builds results/report.md from the raw JSONL files only.

import { CLEANUP_MODELS, type CleanupRow, cleanupSets } from "./cleanup.ts";
import {
	type AudioInfo,
	BENCH_SEED,
	type Clip,
	DURATION_BUCKETS,
	type DictionaryEntry,
	type Paths,
	applyDictionary,
	dictionaryTerms,
	durationBucket,
	loadReferences,
	mulberry32,
} from "./data.ts";
import { okRowsByVariant, readJsonl, sumCost } from "./openrouter.ts";
import { shortDiff, termRecall, wer } from "./score.ts";
import { type RunEvent, type SttRow, LATENCY_CLIPS, bestSttVariant, sameTextRate, sttVariants } from "./stt.ts";

export function percentile(values: number[], p: number): number | null {
	if (!values.length) return null;
	const sorted = [...values].sort((a, b) => a - b);
	return sorted[Math.max(0, Math.ceil(p * sorted.length) - 1)]!;
}

const fmtMs = (v: number | null) => (v === null ? "-" : `${Math.round(v)}`);
const fmtPct = (num: number, den: number) => (den ? `${((100 * num) / den).toFixed(1)}%` : "-");
const fmtUsd = (v: number) => `$${v.toFixed(4)}`;
const ist = (iso: string) =>
	new Date(iso).toLocaleString("en-GB", { timeZone: "Asia/Kolkata", dateStyle: "medium", timeStyle: "medium" });

export function table(head: string[], rows: (string | number)[][]): string {
	const esc = (c: string | number) => String(c).replaceAll("|", "\\|").replaceAll("\n", " ");
	return [
		`| ${head.join(" | ")} |`,
		`| ${head.map(() => "---").join(" | ")} |`,
		...rows.map((r) => `| ${r.map(esc).join(" | ")} |`),
	].join("\n");
}

type ClipErrors = { errors: number; words: number };
type Scored = { errors: number; words: number; hits: number; terms: number; n: number; perClip: ClipErrors[] };

/** Corpus WER and term recall of `hyp(clip)` over `clips`; clips without a hypothesis are left out and counted. */
function score(clips: Clip[], hyp: (c: Clip) => string | null | undefined, terms: string[], ref = (c: Clip) => c.reference): Scored {
	const s: Scored = { errors: 0, words: 0, hits: 0, terms: 0, n: 0, perClip: [] };
	for (const c of clips) {
		const h = hyp(c);
		if (h == null) continue;
		const w = wer(ref(c), h);
		const t = termRecall(ref(c), h, terms);
		s.errors += w.errors;
		s.words += w.refWords;
		s.hits += t.hits;
		s.terms += t.total;
		s.n++;
		s.perClip.push({ errors: w.errors, words: w.refWords });
	}
	return s;
}

/** 95% percentile-bootstrap CI of corpus WER: resample clips with replacement, seeded with BENCH_SEED. */
function werCi(perClip: ClipErrors[], rounds = 2000): [number, number] | null {
	if (!perClip.length) return null;
	const rand = mulberry32(BENCH_SEED);
	const rates: number[] = [];
	for (let b = 0; b < rounds; b++) {
		let errors = 0;
		let words = 0;
		for (let i = 0; i < perClip.length; i++) {
			const c = perClip[Math.floor(rand() * perClip.length)]!;
			errors += c.errors;
			words += c.words;
		}
		if (words) rates.push(errors / words);
	}
	const lo = percentile(rates, 0.025);
	const hi = percentile(rates, 0.975);
	return lo === null || hi === null ? null : [lo, hi];
}

const werCell = (s: Scored, of: number) => `${fmtPct(s.errors, s.words)} (${s.n}/${of})`;
const termCell = (s: Scored) => `${fmtPct(s.hits, s.terms)} (${s.hits}/${s.terms})`;

export async function writeReport(p: Paths, clips: Clip[], dict: DictionaryEntry[]): Promise<string> {
	const terms = dictionaryTerms(dict);
	const audio = new Map((await readJsonl<AudioInfo>(p.audioIndex)).map((r) => [r.clipId, r]));
	const sttRows = await readJsonl<SttRow>(p.sttRaw);
	const cleanupRows = await readJsonl<CleanupRow>(p.cleanupRaw);
	const latencyRows = await readJsonl<SttRow>(p.latencyRaw);
	const events = await readJsonl<RunEvent>(p.runLog);
	const ok = okRowsByVariant(sttRows);
	const edited = clips.filter((c) => c.refSource === "edited");
	const dur = (c: Clip) => audio.get(c.id)?.durationSec ?? null;
	const out: string[] = [];

	const sttCost = sumCost(sttRows);
	const cleanupCost = sumCost(cleanupRows);
	const latencyCost = sumCost(latencyRows);
	const probeCost = sumCost(await readJsonl<SttRow>(p.probeRaw));
	const byField = (f: Clip["refField"]) => clips.filter((c) => c.refField === f).length;

	out.push(
		"# kotoba-bench-v1 report",
		"",
		`Generated ${ist(new Date().toISOString())} IST from the raw JSONL files in this folder.`,
		"",
		"## Data",
		"",
		`- Clips with a reference and audio: ${clips.length}. Edited subset (editedText differs from formattedText): ${edited.length}.`,
		`- Reference field: editedText ${byField("editedText")}, pastedText ${byField("pastedText")}, formattedText ${byField("formattedText")}.`,
		`- Audio indexed: ${audio.size}, total ${(([...audio.values()].reduce((s, a) => s + a.durationSec, 0)) / 60).toFixed(1)} min.`,
		`- Cost from raw files: STT ${fmtUsd(sttCost)}, cleanup ${fmtUsd(cleanupCost)}, latency pass ${fmtUsd(latencyCost)}, option probes ${fmtUsd(probeCost)}, total ${fmtUsd(sttCost + cleanupCost + latencyCost + probeCost)}.`,
		"- WER: corpus WER = (S + D + I) / reference words after normalization (lowercase, punctuation removed except inside identifier-shaped tokens, fillers um/uh/erm/hmm dropped). Cells show `WER (clips scored/clips in set)`.",
		"- Term recall: technical reference tokens (inner `_ . / - :`, camelCase, letters+digits, backticked, or dictionary terms) found exactly, case-sensitive, in the output.",
		"- Caveat: outside the edited subset the reference is Wispr's own pasted/formatted text, so the 'all' columns favor Wispr formattedText and any output that formats like it. Use the edited columns to compare.",
		"",
	);

	// --- STT ---
	const variants = sttVariants(dict);
	const variantKeys = [...new Set([...variants.map((v) => v.key), ...ok.keys()])];
	const sttTable: (string | number)[][] = [];
	/** One STT table row: accuracy cells over all clips and the edited subset, then `rest`. */
	const sttRow = (label: string, hyp: (c: Clip) => string | null | undefined, rest: (string | number)[]) => {
		const all = score(clips, hyp, terms);
		const ed = score(edited, hyp, terms);
		sttTable.push([label, werCell(all, clips.length), werCell(ed, edited.length), termCell(all), termCell(ed), ...rest]);
	};
	for (const key of variantKeys) {
		const byClip = ok.get(key) ?? new Map<string, SttRow>();
		const all = sttRows.filter((r) => r.variant === key);
		if (!all.length) continue;
		const okRows = [...byClip.values()];
		const failed = all.filter((r) => !r.ok);
		const statuses = [...new Set(failed.map((r) => r.status))].join(",");
		const lat = okRows.map((r) => r.latencyMs);
		const base = variants.find((v) => v.key === key)?.base;
		const sameRate = base ? sameTextRate(ok, key, base) : null;
		sttRow(key, (c) => byClip.get(c.id)?.text, [
			fmtMs(percentile(lat, 0.5)),
			fmtMs(percentile(lat, 0.9)),
			okRows.length ? `${(okRows.reduce((s, r) => s + r.audioBytes, 0) / okRows.length / 1024).toFixed(0)} KB` : "-",
			[...new Set(okRows.map((r) => r.format))].join(",") || "-",
			fmtUsd(sumCost(all)),
			failed.length ? `${failed.length} (${statuses})` : "0",
			sameRate ? `${(100 * sameRate.rate).toFixed(1)}% of ${sameRate.pairs}` : "-",
		]);
	}
	const e2e = clips.flatMap((c) => (typeof c.e2eLatency === "number" ? [c.e2eLatency] : []));
	const wisprLatency = [`${fmtMs(percentile(e2e, 0.5))}*`, `${fmtMs(percentile(e2e, 0.9))}*`, "-", "-", "-", "-", "-"];
	sttRow("Wispr asrText", (c) => c.asrText, wisprLatency);
	sttRow("Wispr formattedText", (c) => c.formattedText, wisprLatency);
	out.push(
		"## STT variants",
		"",
		table(
			["variant", "WER all", "WER edited", "term recall all", "term recall edited", "contended lat p50 ms", "contended lat p90 ms", "mean upload", "format", "cost", "failed attempts (status)", "same text as base"],
			sttTable,
		),
		"",
		"Contended latency = request start to full response body during the accuracy pass (many uploads in flight on one home uplink): not for gates; see the latency gate pass below. *Wispr rows show Wispr e2eLatency in ms; what it spans is not documented. 'same text as base' near 100% means the provider option was probably dropped. Passthrough variants run on a probe set first and extend to every clip only below 90% same text (see run log).",
		"",
	);

	// --- Latency gate pass ---
	const latencyOk = okRowsByVariant(latencyRows);
	out.push("## Latency gate pass (sequential, 10-20 s clips)", "");
	if (!latencyRows.length) {
		out.push("Not run yet (`--only latency`).", "");
	} else {
		const gateRows: (string | number)[][] = [];
		const gateClipIds = new Set<string>();
		for (const [key, byClip] of latencyOk) {
			const rs = [...byClip.values()];
			for (const r of rs) gateClipIds.add(r.clipId);
			const lat = rs.map((r) => r.latencyMs);
			gateRows.push([
				key,
				rs.length,
				fmtMs(percentile(lat, 0.5)),
				fmtMs(percentile(lat, 0.9)),
				fmtMs(Math.max(...lat)),
				`${(rs.reduce((s, r) => s + r.audioBytes, 0) / rs.length / 1024).toFixed(0)} KB`,
				[...new Set(rs.map((r) => r.format))].join(","),
				fmtUsd(sumCost(latencyRows.filter((r) => r.variant === key))),
				latencyRows.filter((r) => r.variant === key && !r.ok).length,
			]);
		}
		const wispr = clips.flatMap((c) => (gateClipIds.has(c.id) && typeof c.e2eLatency === "number" ? [c.e2eLatency] : []));
		gateRows.push(["Wispr e2eLatency, same clips", wispr.length, fmtMs(percentile(wispr, 0.5)), fmtMs(percentile(wispr, 0.9)), wispr.length ? fmtMs(Math.max(...wispr)) : "-", "-", "-", "-", "-"]);
		out.push(
			table(["variant", "n", "p50 ms", "p90 ms", "max ms", "mean upload", "format", "cost", "failed attempts"], gateRows),
			"",
			`One request at a time, providers alternating per clip, seeded sample of up to ${LATENCY_CLIPS} clips from the 10-20 s bucket. Latency = request start to full response body, through OpenRouter, from this Mac. These are the gate numbers. Wispr e2eLatency is in ms; what it spans is not documented.`,
			"",
		);
	}

	// --- Latency by duration bucket ---
	const bucketRows: (string | number)[][] = [];
	const bucketCell = (vals: number[]) =>
		vals.length ? `${fmtMs(percentile(vals, 0.5))} / ${fmtMs(percentile(vals, 0.9))} (n=${vals.length})` : "-";
	for (const key of variantKeys) {
		const okRows = [...(ok.get(key)?.values() ?? [])];
		if (!okRows.length) continue;
		bucketRows.push([
			key,
			...DURATION_BUCKETS.map((b) => bucketCell(okRows.filter((r) => durationBucket(r.audioSec) === b).map((r) => r.latencyMs))),
		]);
	}
	bucketRows.push([
		"Wispr e2eLatency (ms, span not documented)",
		...DURATION_BUCKETS.map((b) =>
			bucketCell(
				clips.flatMap((c) => {
					const d = dur(c);
					return d !== null && durationBucket(d) === b && typeof c.e2eLatency === "number" ? [c.e2eLatency] : [];
				}),
			),
		),
	]);
	out.push("## Contended latency p50 / p90 (ms) by audio duration (accuracy pass, not for gates)", "", table(["variant", ...DURATION_BUCKETS], bucketRows), "");

	// --- Cleanup ---
	// One table per (STT input seen in the cleanup rows, clip set).
	const best = bestSttVariant(clips, ok);
	const sources = [...new Set([...cleanupRows.map((r) => r.sttVariant), ...(best ? [best] : [])])];
	const sets = cleanupSets(clips);
	const cleanupSetsShown = [
		{ title: `edited subset (n=${sets.edited.length}, noisy), reference = editedText`, set: sets.edited, ref: (c: Clip) => c.reference },
		{
			title: `seeded sample (n=${sets.sample.length}), reference = pastedText (proxy: matches Wispr's accepted output)`,
			set: sets.sample,
			ref: (c: Clip) => c.pastedText ?? "",
		},
	];
	out.push("## Cleanup", "");
	if (!sources.length) out.push("No STT variant covers 90% of the scored clips yet.", "");
	for (const source of sources) {
		const raw = (c: Clip) => ok.get(source)?.get(c.id)?.text;
		const keys = [...new Set([...CLEANUP_MODELS.map((m) => m.key), ...cleanupRows.map((r) => r.variant)])];
		for (const { title, set, ref } of cleanupSetsShown) {
			const ids = new Set(set.map((c) => c.id));
			const rows: (string | number)[][] = [];
			for (const key of keys) {
				const mine = cleanupRows.filter((r) => r.variant === key && r.sttVariant === source && ids.has(r.clipId));
				if (!mine.length) continue;
				const firstOk = okRowsByVariant(mine).get(key) ?? new Map<string, CleanupRow>();
				const okRows = [...firstOk.values()];
				const ttft = okRows.flatMap((r) => (r.ttftMs === null ? [] : [r.ttftMs]));
				const total = okRows.map((r) => r.totalMs);
				const s = score(set, (c) => firstOk.get(c.id)?.text, terms, ref);
				const providers = [...new Set(okRows.map((r) => r.provider ?? "?"))].join(",");
				const reasoning = okRows.reduce(
					(sum, r) =>
						sum + (Number((r.usage?.completion_tokens_details as { reasoning_tokens?: number } | undefined)?.reasoning_tokens) || 0),
					0,
				);
				rows.push([
					key,
					werCell(s, set.length),
					termCell(s),
					fmtMs(percentile(ttft, 0.5)),
					fmtMs(percentile(ttft, 0.9)),
					fmtMs(percentile(total, 0.5)),
					fmtMs(percentile(total, 0.9)),
					okRows.length ? (reasoning / okRows.length).toFixed(1) : "-",
					providers,
					fmtUsd(sumCost(mine)),
					mine.length - okRows.length,
				]);
			}
			const noLlm = (label: string, hyp: (c: Clip) => string | null | undefined) => {
				const s = score(set, hyp, terms, ref);
				rows.push([label, werCell(s, set.length), termCell(s), "-", "-", "-", "-", "-", "-", "$0", "-"]);
			};
			noLlm(`raw ${source} (no cleanup)`, raw);
			noLlm(`raw ${source} + find/replace`, (c) => {
				const t = raw(c);
				return t == null ? t : applyDictionary(t, dict);
			});
			noLlm("Wispr formattedText", (c) => c.formattedText);
			out.push(
				`### Input \`${source}\`, ${title}`,
				"",
				table(
					["variant", "WER", "term recall", "TTFT p50 ms", "TTFT p90 ms", "total p50 ms", "total p90 ms", "mean reasoning tokens", "provider", "cost", "failed attempts"],
					rows,
				),
				"",
			);
		}
	}
	out.push(
		`Input STT variant: lowest WER over all scored clips among variants with 90% coverage (now \`${best ?? "-"}\`). TTFT = request start to first non-empty content token; total = request start to end of stream. Cleanup latency was measured with many requests in flight: contended, not for gates. Against pastedText, Wispr formattedText is near 0% by construction.`,
		"",
	);

	// --- Worst clips ---
	out.push("## 10 worst clips per STT variant", "", "Diff legend: `[ref→hyp]` substitution, `-word` deletion, `+word` insertion, `…` 3+ matching words.", "");
	const clipById = new Map(clips.map((c) => [c.id, c]));
	for (const key of variantKeys) {
		const okRows = [...(ok.get(key)?.values() ?? [])];
		if (!okRows.length) continue;
		const scored = okRows.flatMap((r) => {
			const c = clipById.get(r.clipId);
			if (!c) return [];
			const w = wer(c.reference, r.text ?? "");
			return [{ c, w, rate: w.refWords ? w.errors / w.refWords : w.errors }];
		});
		scored.sort((a, b) => b.rate - a.rate || b.w.errors - a.w.errors);
		out.push(
			`### ${key}`,
			"",
			table(
				["clip", "ref", "dur s", "WER", "errors/words", "diff"],
				scored.slice(0, 10).map(({ c, w, rate }) => [
					c.id,
					c.refSource,
					dur(c)?.toFixed(1) ?? "-",
					`${(100 * rate).toFixed(0)}%`,
					`${w.errors}/${w.refWords}`,
					shortDiff(w.ops),
				]),
			),
			"",
		);
	}

	// --- Owner references ---
	// Hand-corrected references from review/ (plus the 18 Wispr edits); the clips that have one.
	const refs = await loadReferences(p);
	const refClips = clips.filter((c) => refs.has(c.id));
	const ownerRef = (c: Clip) => refs.get(c.id)!.text;
	const fromOwner = refClips.filter((c) => refs.get(c.id)!.source === "owner").length;
	out.push("## Owner references", "");
	if (!refClips.length) {
		out.push("No hand-corrected references yet (`references.jsonl`).", "");
	} else {
		type Hyp = { label: string; hyp: (c: Clip) => string | null | undefined };
		const hyps: Hyp[] = variantKeys
			.filter((key) => ok.has(key))
			.map((key) => ({ label: key, hyp: (c: Clip) => ok.get(key)!.get(c.id)?.text }));
		hyps.push({ label: "Wispr asrText", hyp: (c) => c.asrText });
		for (const source of sources) {
			const withCleanup = new Set<string>();
			for (const key of [...new Set(cleanupRows.map((r) => r.variant))]) {
				const byClip = okRowsByVariant(cleanupRows.filter((r) => r.variant === key && r.sttVariant === source)).get(key);
				if (!byClip) continue;
				for (const id of byClip.keys()) withCleanup.add(id);
				hyps.push({ label: `cleanup ${key} (input ${source})`, hyp: (c) => byClip.get(c.id)?.text });
			}
			if (withCleanup.size) {
				hyps.push({
					label: `raw ${source}, clips with cleanup output`,
					hyp: (c) => (withCleanup.has(c.id) ? ok.get(source)?.get(c.id)?.text : undefined),
				});
			}
		}
		const scored = hyps.map((h) => ({ ...h, s: score(refClips, h.hyp, terms, ownerRef) }));
		out.push(
			`${refClips.length} clips have a hand-corrected reference: ${fromOwner} from the owner, ${refClips.length - fromOwner} Wispr edits. The last row per clip in references.jsonl wins.`,
			"",
			table(
				["variant", "n", "WER", "WER 95% CI", "term recall"],
				scored.map(({ label, s }) => {
					const ci = werCi(s.perClip);
					return [
						label,
						s.n,
						fmtPct(s.errors, s.words),
						ci ? `${(100 * ci[0]).toFixed(1)}-${(100 * ci[1]).toFixed(1)}%` : "-",
						termCell(s),
					];
				}),
			),
			"",
			"CI: 95% percentile bootstrap over clips (2000 resamples, seed BENCH_SEED). Cleanup rows cover only clips in the cleanup sets; compare them with the raw row on the same clips.",
			"",
		);
		const buckets = DURATION_BUCKETS.filter((b) => refClips.filter((c) => dur(c) !== null && durationBucket(dur(c)!) === b).length >= 5);
		if (buckets.length) {
			const inBucket = (b: string) => refClips.filter((c) => dur(c) !== null && durationBucket(dur(c)!) === b);
			out.push(
				"WER by audio duration (buckets with 5 or more reference clips; a cell needs 5 or more scored clips):",
				"",
				table(
					["variant", ...buckets],
					scored.map(({ label, hyp }) => [
						label,
						...buckets.map((b) => {
							const s = score(inBucket(b), hyp, terms, ownerRef);
							return s.n >= 5 ? `${fmtPct(s.errors, s.words)} (n=${s.n})` : "-";
						}),
					]),
				),
				"",
			);
		}
	}

	if (events.length) {
		out.push("## Run log", "", table(["at (IST)", "event", "variant", "detail"], events.map((e) => [ist(e.at), e.event, e.variant ?? "-", e.detail])), "");
	}

	const md = `${out.join("\n")}\n`;
	await Bun.write(p.report, md);
	return md;
}
