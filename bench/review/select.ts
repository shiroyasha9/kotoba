// Picks the clips the owner hand-corrects into references for kotoba-bench.

import {
	BENCH_SEED,
	DURATION_BUCKETS,
	type DurationBucket,
	type ManifestRow,
	durationBucket,
	mulberry32,
	pickReference,
	present,
	shuffle,
} from "../data.ts";
import { type RawRow, okRowsByVariant } from "../openrouter.ts";
import { align, normalize } from "../score.ts";
import type { SttVariantKey } from "../stt.ts";

export const PREFILL_VARIANT = "mai+phraseList" satisfies SttVariantKey;
export const ALT_VARIANT = "grok+keyterms" satisfies SttVariantKey;
export const SAMPLE_SIZE = 50;

/** The owner already corrected Wispr's text for this clip, so it has a reference. */
export const isEdited = (r: ManifestRow) => pickReference(r)?.refSource === "edited";

export type Candidate = {
	id: string;
	app: string | null;
	duration: number;
	bucket: DurationBucket;
	mai: string;
	grok: string | null;
	asr: string | null;
	formatted: string | null;
	/** Mean pairwise word distance between mai+phraseList, grok+keyterms and Wispr asrText (0 = all agree). */
	disagreement: number;
};

/** Word errors over the longer normalized text, so it is symmetric and in [0, 1]. */
export function wordDistance(a: string, b: string): number {
	const x = normalize(a);
	const y = normalize(b);
	const longer = Math.max(x.length, y.length);
	return longer ? align(x, y).filter((o) => o.op !== "ok").length / longer : 0;
}

function disagreement(texts: string[]): number {
	const d: number[] = [];
	for (let i = 0; i < texts.length; i++) {
		for (let j = i + 1; j < texts.length; j++) d.push(wordDistance(texts[i]!, texts[j]!));
	}
	return d.length ? d.reduce((s, v) => s + v, 0) / d.length : 0;
}

/** Non-edited clips with a duration and a successful mai+phraseList transcript (first ok row per variant wins). */
export function candidates(manifest: ManifestRow[], stt: RawRow[]): Candidate[] {
	const ok = okRowsByVariant(stt);
	const out: Candidate[] = [];
	for (const row of manifest) {
		const id = row.transcriptEntityId;
		const mai = ok.get(PREFILL_VARIANT)?.get(id)?.text;
		if (isEdited(row) || mai == null || row.duration == null) continue;
		const grok = ok.get(ALT_VARIANT)?.get(id)?.text ?? null;
		const asr = present(row.asrText) ? row.asrText : null;
		out.push({
			id,
			app: row.app,
			duration: row.duration,
			bucket: durationBucket(row.duration),
			mai,
			grok,
			asr,
			formatted: row.formattedText,
			disagreement: disagreement([mai, grok, asr].filter((t): t is string => t != null)),
		});
	}
	return out.sort((a, b) => a.id.localeCompare(b.id));
}

/** Equal share per bucket; a bucket with too few clips passes its spare slots to the larger ones. */
export function allocate(sizes: Record<DurationBucket, number>, n: number): Record<DurationBucket, number> {
	const out = {} as Record<DurationBucket, number>;
	// Array sort is stable, so equal sizes keep bucket order.
	const order = [...DURATION_BUCKETS].sort((a, b) => sizes[a] - sizes[b]);
	let left = n;
	order.forEach((b, i) => {
		out[b] = Math.min(sizes[b], Math.ceil(left / (order.length - i)));
		left -= out[b];
	});
	return out;
}

/**
 * Seeded, duration-stratified sample that favours disagreement: inside each bucket,
 * weighted sampling without replacement (Efraimidis-Spirakis, key = u^(1/w)) with
 * weight 0.05 + disagreement. The result is shuffled so buckets interleave.
 */
export function selectClips(pool: Candidate[], n = SAMPLE_SIZE, seed = BENCH_SEED): Candidate[] {
	const rand = mulberry32(seed);
	const byBucket = new Map<DurationBucket, Candidate[]>(DURATION_BUCKETS.map((b) => [b, []]));
	for (const c of [...pool].sort((a, b) => a.id.localeCompare(b.id))) byBucket.get(c.bucket)!.push(c);
	const sizes = Object.fromEntries(DURATION_BUCKETS.map((b) => [b, byBucket.get(b)!.length])) as Record<DurationBucket, number>;
	const quota = allocate(sizes, n);
	const picked: Candidate[] = [];
	for (const b of DURATION_BUCKETS) {
		const keyed = byBucket.get(b)!.map((c) => ({ c, key: Math.pow(rand(), 1 / (0.05 + c.disagreement)) }));
		keyed.sort((x, y) => y.key - x.key);
		picked.push(...keyed.slice(0, quota[b]).map((k) => k.c));
	}
	return shuffle(picked, rand);
}
