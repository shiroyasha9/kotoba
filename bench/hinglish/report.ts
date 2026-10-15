// Builds results/report.md for the synthetic Hinglish bench from the raw JSONL files only.

import { okRowsByVariant, readJsonl, sumCost } from "../openrouter.ts";
import { percentile, table } from "../report.ts";
import { type SttRow, sameTextRate } from "../stt.ts";
import {
	type Wer,
	corpusRate,
	hasDevanagari,
	romanize,
	scriptShare,
	translitTable,
	werDirect,
	werRomanized,
} from "./score.ts";
import type { TextSet } from "./texts.ts";
import { type HinglishClip, type HinglishPaths, TTS_MODEL, TTS_STYLE, type TtsRow, VOICES } from "./tts.ts";
import { LATENCY_CLIPS, VARIANTS } from "./variants.ts";

const pct = (v: number | null) => (v === null ? "-" : `${(100 * v).toFixed(1)}%`);
const ms = (v: number | null) => (v === null ? "-" : `${Math.round(v)}`);
const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
/** Base for the same-text check: identical output to auto-detect suggests a `language` option was dropped. */
const AUTO = "mai+auto";
const SET_NAMES: Record<TextSet, string> = {
	hinglish: "Set H: Hinglish (romanized reference)",
	hindi: "Set D: Hindi (Devanagari reference)",
};

export async function writeHinglishReport(p: HinglishPaths, clips: HinglishClip[]): Promise<string> {
	const [ttsRows, sttRows, latRows] = await Promise.all([
		readJsonl<TtsRow>(p.ttsRaw),
		readJsonl<SttRow>(p.sttRaw),
		readJsonl<SttRow>(p.latencyRaw),
	]);
	const stt = okRowsByVariant(sttRows);
	const lat = okRowsByVariant(latRows);
	const tts = new Map(ttsRows.filter((r) => r.ok).map((r) => [r.clipId, r]));
	const voiced = clips.filter((c) => tts.has(c.id));
	const translit = await translitTable([
		...clips.map((c) => c.reference),
		...sttRows.flatMap((r) => (r.ok && r.text ? [r.text] : [])),
	]);

	const out: string[] = [
		"# Synthetic Hinglish bench",
		"",
		`Generated ${new Date().toISOString()} from \`results/tts-raw.jsonl\`, \`stt-raw.jsonl\` and \`latency-raw.jsonl\`.`,
		"",
		"## TTS",
		"",
		`Model \`${TTS_MODEL}\`, voices ${VOICES.join(", ")}, 24 kHz PCM. Style: "${TTS_STYLE}"`,
		"",
		table(
			["Clips ok", "Attempts", "Audio", "Clip length p50 / min / max", "Cost (generation / estimate rows)"],
			[
				[
					`${voiced.length} of ${clips.length}`,
					ttsRows.length,
					`${(voiced.reduce((s, c) => s + tts.get(c.id)!.audioSec, 0) / 60).toFixed(1)} min`,
					(() => {
						const secs = voiced.map((c) => tts.get(c.id)!.audioSec);
						return secs.length
							? `${percentile(secs, 0.5)!.toFixed(1)} / ${Math.min(...secs).toFixed(1)} / ${Math.max(...secs).toFixed(1)} s`
							: "-";
					})(),
					`$${sumCost(ttsRows).toFixed(4)} (${ttsRows.filter((r) => r.costSource === "generation").length} / ${ttsRows.filter((r) => r.costSource === "estimate").length})`,
				],
			],
		),
		"",
		`STT cost: $${(sumCost(sttRows) + sumCost(latRows)).toFixed(4)} (accuracy $${sumCost(sttRows).toFixed(4)}, latency $${sumCost(latRows).toFixed(4)}).`,
	];

	for (const set of ["hinglish", "hindi"] as const) {
		const inSet = voiced.filter((c) => c.text.set === set);
		if (!inSet.length) continue;
		const ids = new Set(inSet.map((c) => c.id));
		out.push("", `## ${SET_NAMES[set]}`, "");
		const rows = VARIANTS.map((v) => {
			const byClip = stt.get(v.key);
			const got = inSet.flatMap((c) => {
				const r = byClip?.get(c.id);
				return r?.text != null ? [{ c, r, text: r.text }] : [];
			});
			const shares = got.map((g) => scriptShare(g.text));
			const latSeq = inSet.flatMap((c) => {
				const r = lat.get(v.key)?.get(c.id);
				return r ? [r.latencyMs] : [];
			});
			const latAcc = got.map((g) => g.r.latencyMs);
			return [
				v.key,
				v.language === undefined ? "en" : (v.language ?? "auto"),
				`${got.length}/${inSet.length}`,
				pct(mean(shares.map((s) => s.latin))),
				pct(mean(shares.map((s) => s.devanagari))),
				pct(mean(shares.map((s) => s.other))),
				got.filter((g) => hasDevanagari(g.text)).length,
				pct(corpusRate(got.map((g) => werDirect(g.c.reference, g.text)))),
				pct(corpusRate(got.map((g) => werRomanized(g.c.reference, g.text, translit)))),
				`${ms(percentile(latAcc, 0.5))} / ${ms(percentile(latAcc, 0.9))}`,
				latSeq.length ? `${ms(percentile(latSeq, 0.5))} / ${ms(percentile(latSeq, 0.9))} (n=${latSeq.length})` : "-",
				v.key === AUTO ? "-" : pct(sameTextRate(stt, v.key, AUTO, ids)?.rate ?? null),
			];
		});
		out.push(
			table(
				[
					"Variant",
					"language",
					"Clips",
					"Latin letters",
					"Devanagari letters",
					"Other letters",
					"Clips with Devanagari",
					"WER",
					"WER romanized (approx.)",
					"Latency p50 / p90 ms, contended",
					"Latency p50 / p90 ms, sequential",
					`Same text as ${AUTO}`,
				],
				rows,
			),
		);

		out.push("", "Romanized WER per voice (approx.):", "");
		out.push(
			table(
				["Variant", ...VOICES],
				VARIANTS.map((v) => [
					v.key,
					...VOICES.map((voice) => {
						const ws: Wer[] = inSet.flatMap((c) => {
							const text = stt.get(v.key)?.get(c.id)?.text;
							return c.voice === voice && text != null ? [werRomanized(c.reference, text, translit)] : [];
						});
						return pct(corpusRate(ws));
					}),
				]),
			),
		);

		const sample = inSet.filter((c) => c.voice === VOICES[0]).slice(0, 3);
		out.push("", "Sample outputs (first voice):", "");
		for (const c of sample) {
			out.push(`- \`${c.id}\` reference: ${c.reference}`);
			for (const v of VARIANTS) {
				const text = stt.get(v.key)?.get(c.id)?.text;
				if (text == null) continue;
				const roman = hasDevanagari(text) ? ` (romanized: ${romanize(text, translit)})` : "";
				out.push(`  - ${v.key}: ${text.replaceAll("\n", " ")}${roman}`);
			}
		}
	}

	out.push(
		"",
		"## Notes",
		"",
		"- WER: lowercase, punctuation and fillers removed, Hinglish spelling folds on both sides (`foldLatin`, `foldDevanagari` in `hinglish/score.ts`). Words in the other script count as errors.",
		"- WER romanized (approx.): every Devanagari word on both sides goes through ICU Devanagari-Latin plus simple schwa deletion and casual-spelling rules, then the same folds. English words that a model writes in Devanagari (डिप्लॉय) seldom come back as the English spelling, so they still count as errors.",
		"- Letter shares: mean per clip over letters only (marks and digits left out).",
		`- Contended latency: accuracy pass, many requests in flight. Sequential latency: one request at a time on ${LATENCY_CLIPS} seeded Hinglish clips.`,
		"- Synthetic speech: one TTS model, clean audio, no room noise. Numbers are a floor on real-speech error, not a measure of it.",
	);
	await Bun.write(p.report, `${out.join("\n")}\n`);
	return p.report;
}
