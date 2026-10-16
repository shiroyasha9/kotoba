// Builds results/report.md and results/pairs.md for the synthetic Writing bench from the raw JSONL files only.

import { join } from "node:path";
import { CLEANUP_MODELS, type CleanupRow, isWritingVariant, variantKey, writingClips } from "../cleanup.ts";
import { type Clip, type DictionaryEntry, dictionaryTerms, loadClips, paths } from "../data.ts";
import { okRowsByVariant, readJsonl, sumCost } from "../openrouter.ts";
import { fmtMs, fmtUsd, ist, percentile, score, table, termCell, werCell } from "../report.ts";
import { wer } from "../score.ts";
import type { SttRow } from "../stt.ts";
import { type SpokenClip, TTS_MODEL, type TtsPaths, type TtsRow } from "../tts.ts";
import type { WritingText } from "./texts.ts";

export type WritingClip = SpokenClip & { text: WritingText };

const WRITING_VARIANTS = CLEANUP_MODELS.map((m) => variantKey(m.key, "writing"));
/** An output that changes more of its transcript than this (word error rate against the transcript) is listed for reading first. */
const REWRITE_FLAG = 0.3;

/** Word error rate of `output` against `input`: how much of the transcript the cleanup changed. */
function rewriteRate(input: string, output: string): number {
	const w = wer(input, output);
	return w.refWords ? w.errors / w.refWords : w.errors;
}

const pct0 = (rate: number) => `${(100 * rate).toFixed(0)}%`;

/** Writing-prompt outputs and their STT input, per clip, from one bench folder's raw files; one STT input (the latest run's). */
async function writingOutputs(sttRaw: string, cleanupRaw: string) {
	const [sttRows, allCleanup] = await Promise.all([readJsonl<SttRow>(sttRaw), readJsonl<CleanupRow>(cleanupRaw)]);
	const source = allCleanup.findLast((r) => isWritingVariant(r.variant))?.sttVariant ?? null;
	const cleanupRows = allCleanup.filter((r) => isWritingVariant(r.variant) && r.sttVariant === source);
	const stt = source ? okRowsByVariant(sttRows).get(source) : undefined;
	return {
		sttRows,
		cleanupRows,
		byVariant: okRowsByVariant(cleanupRows),
		source,
		transcript: (id: string) => stt?.get(id)?.text ?? null,
	};
}

type Outputs = Awaited<ReturnType<typeof writingOutputs>>;

function pairBlock(heading: string, head: [string, string][], c: Clip, o: Outputs): string[] {
	const input = o.transcript(c.id);
	const lines = [`### ${heading}`, "", ...head.map(([k, v]) => `- **${k}:** ${v}`)];
	lines.push(`- **Transcript (${o.source ?? "-"}):** ${input ?? "-"}`);
	for (const key of WRITING_VARIANTS) {
		const text = o.byVariant.get(key)?.get(c.id)?.text;
		const change = text && input ? ` _(changed ${pct0(rewriteRate(input, text))} of the transcript)_` : "";
		lines.push(`- **${key}:**${change} ${text ?? "-"}`);
	}
	return [...lines, ""];
}

export async function writeWritingReport(
	p: TtsPaths,
	clips: WritingClip[],
	dict: DictionaryEntry[],
	realDir?: string,
): Promise<{ report: string; pairs: string }> {
	const terms = dictionaryTerms(dict);
	const [ttsRows, o] = await Promise.all([readJsonl<TtsRow>(p.ttsRaw), writingOutputs(p.sttRaw, p.cleanupRaw)]);
	const tts = new Map(ttsRows.filter((r) => r.ok).map((r) => [r.clipId, r]));
	const traps = clips.filter((c) => c.text.trap);
	const plain = clips.filter((c) => !c.text.trap);

	const out: string[] = [
		"# Synthetic Writing bench",
		"",
		`Generated ${ist(new Date().toISOString())} IST from \`results/tts-raw.jsonl\`, \`stt-raw.jsonl\` and \`cleanup-raw.jsonl\`.`,
		"",
		`- TTS: \`${TTS_MODEL}\`, ${tts.size} of ${clips.length} clips, ${([...tts.values()].reduce((s, r) => s + r.audioSec, 0) / 60).toFixed(1)} min audio.`,
		`- Cost from raw files: TTS ${fmtUsd(sumCost(ttsRows))} (listed-price estimate unless /generation listed it), STT ${fmtUsd(sumCost(o.sttRows))}, cleanup ${fmtUsd(sumCost(o.cleanupRows))}.`,
		`- Reference: the text the speaker meant to write (\`writing/texts.ts\`). Cleanup input: \`${o.source ?? "-"}\`.`,
		"- WER and term recall as in kotoba-bench-v1 (`score.ts`); term recall counts technical reference tokens and dictionary terms found exactly.",
		"",
	];

	const sets: [string, WritingClip[]][] = [
		[`clips from Writing apps (synthetic, n=${clips.length}), Writing prompt, reference = intended text`, clips],
		[`traps (n=${traps.length}): questions and commands that the prompt must not answer or obey`, traps],
		[`no trap (n=${plain.length})`, plain],
	];
	for (const [title, set] of sets) {
		const ids = new Set(set.map((c) => c.id));
		const rows: (string | number)[][] = [];
		for (const key of WRITING_VARIANTS) {
			const mine = o.cleanupRows.filter((r) => r.variant === key && ids.has(r.clipId));
			if (!mine.length) continue;
			const firstOk = o.byVariant.get(key) ?? new Map<string, CleanupRow>();
			const okRows = [...firstOk.values()].filter((r) => ids.has(r.clipId));
			const ttft = okRows.flatMap((r) => (r.ttftMs === null ? [] : [r.ttftMs]));
			const total = okRows.map((r) => r.totalMs);
			const s = score(set, (c) => firstOk.get(c.id)?.text, terms);
			rows.push([
				key,
				werCell(s, set.length),
				termCell(s),
				fmtMs(percentile(ttft, 0.5)),
				fmtMs(percentile(ttft, 0.9)),
				fmtMs(percentile(total, 0.5)),
				fmtMs(percentile(total, 0.9)),
				fmtUsd(sumCost(mine)),
				mine.length - okRows.length,
			]);
		}
		const raw = score(set, (c) => o.transcript(c.id), terms);
		rows.push([`raw ${o.source ?? "-"} (no cleanup)`, werCell(raw, set.length), termCell(raw), "-", "-", "-", "-", "$0", "-"]);
		out.push(
			`## ${title}`,
			"",
			table(["variant", "WER", "term recall", "TTFT p50 ms", "TTFT p90 ms", "total p50 ms", "total p90 ms", "cost", "failed attempts"], rows),
			"",
		);
	}
	out.push(
		"Cleanup latency was measured with many requests in flight: contended, not for gates.",
		"",
		`## Outputs that changed more than ${100 * REWRITE_FLAG}% of their transcript`,
		"",
		"Read these first in `pairs.md`: an answer or an obeyed command changes most of the transcript.",
		"",
	);
	const flagged = clips.flatMap((c) => {
		const input = o.transcript(c.id);
		if (!input) return [];
		return WRITING_VARIANTS.flatMap((key) => {
			const text = o.byVariant.get(key)?.get(c.id)?.text;
			if (!text) return [];
			const rate = rewriteRate(input, text);
			return rate > REWRITE_FLAG ? [{ c, key, rate }] : [];
		});
	});
	flagged.sort((a, b) => b.rate - a.rate);
	out.push(
		flagged.length
			? table(["clip", "trap", "variant", "changed"], flagged.map(({ c, key, rate }) => [c.id, c.text.trap ?? "-", key, pct0(rate)]))
			: "None.",
		"",
	);
	await Bun.write(p.report, `${out.join("\n")}\n`);

	const pairs = [
		"# Writing prompt: every input and output",
		"",
		`Generated ${ist(new Date().toISOString())} IST. Each block: what the speaker meant, the STT transcript the cleanup got, and each model's Writing-prompt output. "Changed" is the word error rate of the output against the transcript.`,
		"",
		"## Synthetic clips (TTS)",
		"",
		...clips.flatMap((c) =>
			pairBlock(`${c.id} · ${c.app}${c.text.trap ? ` · trap: ${c.text.trap}` : ""}`, [["Spoken (TTS input)", c.text.spoken], ["Meant", c.reference]], c, o),
		),
	];
	if (realDir) {
		const rp = paths(realDir);
		const [loaded, ro] = await Promise.all([loadClips(rp), writingOutputs(rp.sttRaw, rp.cleanupRaw)]);
		const real = writingClips(loaded.clips);
		pairs.push(
			"## Real clips from Writing apps (kotoba-bench-v1)",
			"",
			...real.flatMap((c) => pairBlock(`${c.id} · ${c.app}`, [[`Reference (${c.refField})`, c.reference]], c, ro)),
		);
	}
	const pairsPath = join(p.results, "pairs.md");
	await Bun.write(pairsPath, `${pairs.join("\n")}\n`);
	return { report: p.report, pairs: pairsPath };
}
