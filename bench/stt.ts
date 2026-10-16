// Speech-to-text pass: every (clip, variant) pair through OpenRouter's
// /audio/transcriptions, one raw JSONL row per HTTP attempt.

import {
	type AudioFormat,
	type AudioInfo,
	type Clip,
	type DictionaryEntry,
	type Paths,
	audioPath,
	dictionaryTerms,
	durationBucket,
	ensureWav16,
	seededSample,
} from "./data.ts";
import {
	API,
	type Budget,
	type CallSink,
	appendJsonl,
	authHeaders,
	loggedCall,
	okRowsByVariant,
	readJsonl,
	retryAfter,
	runCalls,
} from "./openrouter.ts";
import { wer } from "./score.ts";

export const GROK = "x-ai/grok-stt-1.0";
export const MAI = "microsoft/mai-transcribe-2";

export type SttVariantKey =
	| "grok"
	| "grok+keyterms"
	| "grok+keyterms+format"
	| "grok+keyterms+fillers"
	| "mai"
	| "mai+phraseList"
	| "mai+clean"
	| "mai+zdr"
	| "mai+auto"
	| "mai+hi"
	| "grok+auto";

/**
 * JSON value for xAI's "true"/"false" form fields (`format`, `filler_words`)
 * under provider.options.xai. Chosen by the 2026-10-15 probe (results/probe-raw.jsonl).
 */
export const XAI_TRUE: string | boolean = "true";

export type SttVariant<K extends string = SttVariantKey> = {
	key: K;
	model: string;
	/** Native provider fields, sent as provider.options.<tag> (OpenRouter STT guide, "Provider-Specific Options"). */
	providerOptions?: Record<string, Record<string, unknown>>;
	/** Variant this one should differ from; identical output on every clip suggests the option was dropped. */
	base?: SttVariantKey;
	/** OpenRouter data-policy routing, sent as top-level `provider` fields next to `options` (STT guide: only `zdr` and `data_collection` apply). */
	routing?: { zdr?: boolean };
	/** Runs in the sequential latency pass only, never in the accuracy pass. */
	latencyOnly?: true;
	/** Top-level ISO-639-1 `language`; null sends none (auto-detect). Default "en". */
	language?: string | null;
};

/**
 * Bias terms: dictionary phrases and replacements. xAI caps `keyterm` at 100
 * terms of up to 50 characters (docs.x.ai speech-to-text reference); the same
 * list goes to Azure `phraseList.phrases`.
 */
export function biasTerms(dict: DictionaryEntry[]): string[] {
	return dictionaryTerms(dict)
		.filter((t) => t.length <= 50)
		.slice(0, 100);
}

export function sttVariants(dict: DictionaryEntry[]): SttVariant[] {
	const terms = biasTerms(dict);
	return [
		{ key: "grok", model: GROK },
		{ key: "grok+keyterms", model: GROK, base: "grok", providerOptions: { xai: { keyterm: terms } } },
		// `format` turns on inverse text normalization (numbers, units); it needs `language`, sent at the top level.
		{
			key: "grok+keyterms+format",
			model: GROK,
			base: "grok+keyterms",
			providerOptions: { xai: { keyterm: terms, format: XAI_TRUE } },
		},
		{
			key: "grok+keyterms+fillers",
			model: GROK,
			base: "grok+keyterms",
			providerOptions: { xai: { keyterm: terms, filler_words: XAI_TRUE } },
		},
		{ key: "mai", model: MAI },
		{
			key: "mai+phraseList",
			model: MAI,
			base: "mai",
			providerOptions: { azure: { phraseList: { phrases: terms } } },
		},
		{
			key: "mai+clean",
			model: MAI,
			base: "mai",
			providerOptions: {
				azure: {
					enhancedMode: { enabled: true, model: "MAI-Transcribe-2", modelOptions: { transcribeStyle: "clean" } },
				},
			},
		},
		// Same request as `mai`, restricted to Zero Data Retention endpoints; measures the latency cost of ZDR.
		{ key: "mai+zdr", model: MAI, routing: { zdr: true }, latencyOnly: true },
	];
}

/** Listed OpenRouter price per audio second, used only for dry-run estimates (the probe measures the real rate). */
export const LISTED_USD_PER_SEC: Record<string, number> = {
	[GROK]: 0.1 / 3600,
	// The models API shows `0.1` with no unit; Microsoft's price is $0.10 per audio hour.
	[MAI]: 0.1 / 3600,
};

export type SttRow = {
	kind: "stt";
	variant: string;
	model: string;
	clipId: string;
	attempt: number;
	startedAt: string;
	status: number;
	ok: boolean;
	latencyMs: number;
	format: AudioFormat;
	audioBytes: number;
	bodyBytes: number;
	audioSec: number;
	cost: number | null;
	text: string | null;
	generationId: string | null;
	body: unknown;
	error?: string;
};

export type RunEvent = {
	at: string;
	event:
		| "flac-probe-failed"
		| "variant-disabled"
		| "variant-skipped"
		| "passthrough-extended"
		| "passthrough-not-extended"
		| "cost-cap"
		| "cleanup-source";
	variant?: string;
	detail: string;
};

export const logEvent = (p: Paths, event: Omit<RunEvent, "at">) =>
	appendJsonl(p.runLog, { at: new Date().toISOString(), ...event });

/**
 * The STT variant with the lowest corpus WER over all scored clips, among
 * variants that cover at least 90% of them (so probe-only variants are out).
 * Cleanup runs on its output. The edited subset (18 clips) is too small to pick on.
 */
export function bestSttVariant(clips: Clip[], ok: Map<string, Map<string, SttRow>>): string | null {
	let best: { key: string; wer: number } | null = null;
	for (const [key, byClip] of ok) {
		let errors = 0;
		let words = 0;
		let covered = 0;
		for (const c of clips) {
			const row = byClip.get(c.id);
			if (!row?.text) continue;
			covered++;
			const w = wer(c.reference, row.text);
			errors += w.errors;
			words += w.refWords;
		}
		if (!clips.length || covered < 0.9 * clips.length || !words) continue;
		const rate = errors / words;
		if (!best || rate < best.wer) best = { key, wer: rate };
	}
	return best?.key ?? null;
}

export type SttJob = { variant: SttVariant<string>; clip: Clip; info: AudioInfo; format: AudioFormat };

export async function transcribe(p: Paths, sink: CallSink, { variant, clip, info, format }: SttJob): Promise<SttRow> {
	const file = format === "flac" ? audioPath(p, clip.id, "flac") : await ensureWav16(p, clip);
	const audio = await Bun.file(file).bytes();
	const body = JSON.stringify({
		model: variant.model,
		input_audio: { data: audio.toBase64(), format },
		...(variant.language === null ? {} : { language: variant.language ?? "en" }),
		...(variant.providerOptions || variant.routing
			? { provider: { ...variant.routing, ...(variant.providerOptions ? { options: variant.providerOptions } : {}) } }
			: {}),
	});
	return loggedCall(sink, async (attempt) => {
		const startedAt = new Date().toISOString();
		const t0 = performance.now();
		let status = 0;
		let parsed: unknown = null;
		let error: string | undefined;
		let generationId: string | null = null;
		let retryAfterSec: number | null = null;
		try {
			const res = await fetch(`${API}/audio/transcriptions`, {
				method: "POST",
				headers: authHeaders(),
				body,
				signal: AbortSignal.timeout(120_000),
			});
			status = res.status;
			generationId = res.headers.get("x-generation-id");
			retryAfterSec = retryAfter(res);
			const text = await res.text();
			try {
				parsed = JSON.parse(text);
			} catch {
				parsed = { raw: text };
			}
			if (!res.ok) error = text.slice(0, 500);
		} catch (e) {
			error = String(e);
		}
		const latencyMs = performance.now() - t0;
		const b = parsed as { text?: string; usage?: { cost?: number } } | null;
		const row: SttRow = {
			kind: "stt",
			variant: variant.key,
			model: variant.model,
			clipId: clip.id,
			attempt,
			startedAt,
			status,
			ok: status === 200 && typeof b?.text === "string",
			latencyMs,
			format,
			audioBytes: audio.byteLength,
			bodyBytes: body.length,
			audioSec: info.durationSec,
			cost: b?.usage?.cost ?? null,
			text: b?.text ?? null,
			generationId,
			body: parsed,
			...(error ? { error } : {}),
		};
		return { row, retryAfterSec };
	});
}

/** A passthrough variant extends past its probe clips only when it matches its base on fewer than this share of them. */
export const SAME_TEXT_LIMIT = 0.9;

/** Share of clips (among `clipIds`) where the variant and its base both succeeded with identical text; null without pairs. */
export function sameTextRate(
	ok: Map<string, Map<string, SttRow>>,
	variant: string,
	base: string,
	clipIds?: Set<string>,
): { rate: number; pairs: number } | null {
	const mine = ok.get(variant);
	const theirs = ok.get(base);
	if (!mine || !theirs) return null;
	let pairs = 0;
	let same = 0;
	for (const [clipId, row] of mine) {
		const other = theirs.get(clipId);
		if (!other || (clipIds && !clipIds.has(clipId))) continue;
		pairs++;
		if (row.text?.trim() === other.text?.trim()) same++;
	}
	return pairs ? { rate: same / pairs, pairs } : null;
}

export type SttContext = {
	p: Paths;
	clips: Clip[];
	audio: Map<string, AudioInfo>;
	dict: DictionaryEntry[];
	budget: Budget;
	concurrency: number;
	dryRun: boolean;
	/** Clips a passthrough variant runs on before the same-text gate; 0 runs every variant on every clip. */
	passthroughProbe: number;
};

/**
 * Base variants run on every clip. Passthrough variants (provider options)
 * first run on `passthroughProbe` clips and extend to every clip only when
 * their output differs from the base often enough to show the option works.
 */
export async function runStt(ctx: SttContext): Promise<void> {
	const { p, clips } = ctx;
	const variants = sttVariants(ctx.dict).filter((v) => !v.latencyOnly);
	const passthrough = variants.filter((v) => v.base);
	if (!ctx.passthroughProbe) {
		await runVariants(ctx, "all variants", variants.map((v) => [v, clips]));
		return;
	}
	const probeClips = clips.slice(0, ctx.passthroughProbe);
	await runVariants(ctx, "base variants", variants.filter((v) => !v.base).map((v) => [v, clips]));
	await runVariants(ctx, `passthrough probe (${probeClips.length} clips)`, passthrough.map((v) => [v, probeClips]));
	if (ctx.dryRun) {
		await runVariants(
			ctx,
			`passthrough extension, worst case (needs same-text rate < ${SAME_TEXT_LIMIT * 100}% on the probe)`,
			passthrough.map((v) => [v, clips]),
		);
		return;
	}
	const ok = okRowsByVariant(await readJsonl<SttRow>(p.sttRaw));
	const probeIds = new Set(probeClips.map((c) => c.id));
	const extend: SttVariant[] = [];
	for (const v of passthrough) {
		const same = sameTextRate(ok, v.key, v.base!, probeIds);
		const pass = same !== null && same.rate < SAME_TEXT_LIMIT;
		const detail = same
			? `same text as ${v.base} on ${(100 * same.rate).toFixed(0)}% of ${same.pairs} probe clips`
			: "no probe pairs";
		await logEvent(p, { event: pass ? "passthrough-extended" : "passthrough-not-extended", variant: v.key, detail });
		console.log(`  ${v.key}: ${detail} -> ${pass ? "extend to all clips" : "probe only"}`);
		if (pass) extend.push(v);
	}
	await runVariants(ctx, "passthrough extension", extend.map((v) => [v, clips]));
}

const FATAL_STATUS = new Set([401, 402]);

/**
 * Runs a variant alone on its shortest pending clip before the pool: this
 * measures the real $/audio-second, catches rejected options or formats, and
 * keeps one bad price unit from spending the budget many calls at a time.
 * Returns null when the variant cannot run.
 */
async function probeVariant(
	ctx: SttContext,
	v: SttVariant,
	left: Clip[],
): Promise<{ row: SttRow; format: AudioFormat } | null> {
	const { p, audio, budget } = ctx;
	const sink = { out: p.sttRaw, budget };
	const clip = left.reduce((a, b) => (audio.get(b.id)!.durationSec < audio.get(a.id)!.durationSec ? b : a));
	const job = { variant: v, clip, info: audio.get(clip.id)! };
	let row = await transcribe(p, sink, { ...job, format: "flac" });
	if (!row.ok && row.status >= 400 && row.status < 500 && !FATAL_STATUS.has(row.status)) {
		await logEvent(p, { event: "flac-probe-failed", variant: v.key, detail: `${row.status} ${row.error ?? ""}` });
		row = await transcribe(p, sink, { ...job, format: "wav" });
	}
	if (FATAL_STATUS.has(row.status)) throw new Error(`OpenRouter returned ${row.status}: ${row.error}`);
	if (!row.ok) {
		await logEvent(p, { event: "variant-disabled", variant: v.key, detail: `probe failed: ${row.status} ${row.error ?? ""}` });
		return null;
	}
	return { row, format: row.format };
}

export async function runVariants(ctx: SttContext, stage: string, targets: [SttVariant, Clip[]][]): Promise<void> {
	const { p, audio, budget } = ctx;
	if (!targets.length || budget.exceeded) return;
	const ok = okRowsByVariant(await readJsonl<SttRow>(p.sttRaw));
	const pending = new Map(targets.map(([v, cs]) => [v.key, cs.filter((c) => !ok.get(v.key)?.has(c.id))]));
	const variants = targets.map(([v]) => v);
	const secs = (cs: Clip[]) => cs.reduce((s, c) => s + (audio.get(c.id)?.durationSec ?? 0), 0);

	console.log(`\nSTT: ${stage}`);
	for (const v of variants) {
		const left = pending.get(v.key)!;
		const est = secs(left) * (LISTED_USD_PER_SEC[v.model] ?? 0);
		console.log(
			`  ${v.key.padEnd(16)} done ${String(ok.get(v.key)?.size ?? 0).padStart(4)}  pending ${String(left.length).padStart(4)}  ` +
				`${(secs(left) / 60).toFixed(1)} min audio  ~$${est.toFixed(3)} at listed price`,
		);
	}
	if (ctx.dryRun) return;

	const formats = new Map<string, AudioFormat>();
	let committed = 0;
	for (const v of variants) {
		const left = pending.get(v.key)!;
		if (!left.length) continue;
		const done = [...(ok.get(v.key)?.values() ?? [])];
		let rate: number;
		if (done.length) {
			formats.set(v.key, done[0]!.format);
			rate = done.reduce((s, r) => s + (r.cost ?? 0), 0) / Math.max(1, done.reduce((s, r) => s + r.audioSec, 0));
		} else {
			if (budget.exceeded) break;
			const probe = await probeVariant(ctx, v, left);
			if (!probe) {
				pending.set(v.key, []);
				continue;
			}
			formats.set(v.key, probe.format);
			rate = (probe.row.cost ?? 0) / Math.max(1, probe.row.audioSec);
			pending.set(v.key, left.filter((c) => c.id !== probe.row.clipId));
		}
		const projected = rate * secs(pending.get(v.key)!);
		if (budget.total + committed + projected > budget.cap) {
			await logEvent(p, {
				event: "variant-skipped",
				variant: v.key,
				detail: `projected $${projected.toFixed(3)} at $${(rate * 3600).toFixed(3)}/audio-hour would pass the $${budget.cap} cap`,
			});
			pending.set(v.key, []);
			continue;
		}
		committed += projected;
		console.log(`  ${v.key}: ${formats.get(v.key)}, $${(rate * 3600).toFixed(3)}/audio-hour, projected $${projected.toFixed(3)}`);
	}

	// Interleave by clip so a cost-cap stop leaves every variant with similar coverage.
	const pendingIds = new Map([...pending].map(([key, cs]) => [key, new Set(cs.map((c) => c.id))]));
	const queue = ctx.clips.flatMap((c) =>
		variants.filter((v) => pendingIds.get(v.key)!.has(c.id)).map((v) => ({ v, c })),
	);
	const sink = { out: p.sttRaw, budget };
	await runCalls(
		"stt",
		queue,
		ctx.concurrency,
		budget,
		({ v, c }) => transcribe(p, sink, { variant: v, clip: c, info: audio.get(c.id)!, format: formats.get(v.key)! }),
		({ v, c }) => `${v.key} ${c.id}`,
	);
	if (budget.exceeded) await logEvent(p, { event: "cost-cap", detail: `stopped STT (${stage}) at $${budget.total.toFixed(4)}` });
}

export const LATENCY_VARIANTS: readonly SttVariantKey[] = ["grok", "mai", "grok+keyterms+format", "mai+zdr"];
export const LATENCY_CLIPS = 40;

/**
 * Gate latency pass: one request at a time, the LATENCY_VARIANTS only, on
 * up to 40 seeded-random 10-20 s clips, reversing the variant order on every
 * other clip. Rows go to latency-raw.jsonl, apart from the contended accuracy pass.
 */
export async function runLatency(ctx: SttContext): Promise<void> {
	const { p, audio, budget } = ctx;
	const variants = sttVariants(ctx.dict).filter((v) => LATENCY_VARIANTS.includes(v.key));
	const bucket = ctx.clips.filter((c) => {
		const d = audio.get(c.id)?.durationSec;
		return d !== undefined && durationBucket(d) === "10-20 s";
	});
	const sample = seededSample(bucket, LATENCY_CLIPS);
	const done = okRowsByVariant(await readJsonl<SttRow>(p.latencyRaw));
	const queue = sample.flatMap((c, i) =>
		(i % 2 ? [...variants].reverse() : variants).filter((v) => !done.get(v.key)?.has(c.id)).map((v) => ({ v, c })),
	);
	console.log(`\nLatency pass: ${sample.length} clips of ${bucket.length} in 10-20 s, ${queue.length} sequential calls pending`);
	if (ctx.dryRun || !queue.length || budget.exceeded) return;
	// Formats come from the accuracy pass (FLAC unless a provider rejected it).
	const ok = okRowsByVariant(await readJsonl<SttRow>(p.sttRaw));
	const sink = { out: p.latencyRaw, budget };
	await runCalls(
		"latency",
		queue,
		1,
		budget,
		({ v, c }) =>
			transcribe(p, sink, {
				variant: v,
				clip: c,
				info: audio.get(c.id)!,
				format: ok.get(v.key)?.values().next().value?.format ?? "flac",
			}),
		({ v, c }) => `${v.key} ${c.id}`,
	);
	if (budget.exceeded) await logEvent(p, { event: "cost-cap", detail: `stopped latency pass at $${budget.total.toFixed(4)}` });
}
