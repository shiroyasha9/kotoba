// TTS pass for the synthetic benches (hinglish/, writing/): each (text, voice) pair through OpenRouter's
// /audio/speech. The PCM body streams to tts/<clip>.pcm, one raw JSONL row per HTTP attempt.

import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";
import { type Clip, paths } from "./data.ts";
import { API, type Budget, type CallSink, authHeaders, loggedCall, readJsonl, retryAfter, runCalls } from "./openrouter.ts";

export const TTS_MODEL = "google/gemini-3.8-flash-lite-tts";
/** Gemini prebuilt voices (OpenRouter `supported_voices`): two female, one male. */
export const VOICES = ["Kore", "Aoede", "Puck"] as const;
/** Sent as top-level `instructions` (OpenRouter TTS guide: Gemini reads it as delivery guidance, not as text). */
export const TTS_STYLE =
	"Speak naturally at a relaxed conversational pace, like an Indian software developer dictating a message to a colleague.";

/** Listed price (models API, 2026-10-16): $0.50 per 1M input tokens, $6 per 1M audio tokens at 25 tokens per second. */
const USD_PER_AUDIO_SEC = (25 * 6) / 1e6;
const USD_PER_INPUT_TOKEN = 0.5 / 1e6;
/** Planning guess for speech length before any audio exists. */
const WORDS_PER_SEC = 2.5;
/** TTS requests in flight, at most. */
export const TTS_CONCURRENCY = 8;
/** Gemini TTS PCM: 16-bit little-endian mono at 24 kHz (Gemini speech-generation docs). */
const PCM_RATE = 24000;

export type TtsPaths = ReturnType<typeof ttsPaths>;

export function ttsPaths(dataDir: string) {
	const p = paths(dataDir);
	const ttsRaw = join(p.results, "tts-raw.jsonl");
	return { ...p, ttsRaw, ttsDir: join(p.results, "tts"), rawFiles: [...p.rawFiles, ttsRaw] };
}

/** A clip the TTS speaks: `text.spoken` in `voice`, written to `wavPath`. */
export type SpokenClip = Clip & { text: { spoken: string }; voice: string };

/** A harness clip for a synthetic text: no Wispr fields; the reference is the text's expected transcript. */
export function spokenClip<T extends { spoken: string }>(
	p: TtsPaths,
	c: { id: string; app: string | null; reference: string; text: T; voice: string },
): Clip & { text: T; voice: string } {
	return {
		transcriptEntityId: c.id,
		timestamp: null,
		app: c.app,
		url: null,
		duration: null,
		numWords: null,
		e2eLatency: null,
		clientNetworkLatency: null,
		asrText: null,
		formattedText: null,
		editedText: c.reference,
		pastedText: null,
		id: c.id,
		wavPath: join(p.clips, `${c.id}.wav`),
		reference: c.reference,
		refSource: "edited",
		refField: "editedText",
		text: c.text,
		voice: c.voice,
	};
}

export type TtsRow = {
	kind: "tts";
	model: string;
	voice: string;
	clipId: string;
	attempt: number;
	startedAt: string;
	status: number;
	ok: boolean;
	latencyMs: number;
	contentType: string | null;
	audioBytes: number;
	audioSec: number;
	inputChars: number;
	/** `total_cost` from /generation, else the listed-price estimate from audioSec. */
	cost: number | null;
	costSource: "generation" | "estimate" | null;
	generationId: string | null;
	/** The /generation response body, kept raw. */
	generation: unknown;
	error?: string;
};

const estimateUsd = (audioSec: number, chars: number) => audioSec * USD_PER_AUDIO_SEC + (chars / 3) * USD_PER_INPUT_TOKEN;

export const plannedSec = (c: SpokenClip) => c.text.spoken.split(/\s+/).length / WORDS_PER_SEC;
export const plannedUsd = (c: SpokenClip) => estimateUsd(plannedSec(c), c.text.spoken.length);

async function durationSec(file: string): Promise<number> {
	return Number((await $`ffprobe -v error -show_entries format=duration -of csv=p=0 ${file}`.text()).trim());
}

/** Fails unless the TTS model is listed by the free speech models endpoint. */
export async function confirmTtsModel(): Promise<void> {
	const res = await fetch(`${API}/models?output_modalities=speech`);
	const ids = new Set(((await res.json()) as { data: { id: string }[] }).data.map((m) => m.id));
	if (!ids.has(TTS_MODEL)) throw new Error(`TTS model not available on OpenRouter: ${TTS_MODEL}`);
}

/** Generation stats, polled: they show up a moment after the response (free GET). */
async function generationStats(id: string): Promise<{ cost: number | null; body: unknown }> {
	let body: unknown = null;
	for (let n = 1; n <= 6; n++) {
		await Bun.sleep(1000 * n);
		const res = await fetch(`${API}/generation?id=${encodeURIComponent(id)}`, { headers: authHeaders() });
		body = await res.json().catch(() => null);
		const cost = (body as { data?: { total_cost?: unknown } } | null)?.data?.total_cost;
		if (res.ok && typeof cost === "number") return { cost, body };
		if (res.status !== 404) break;
	}
	return { cost: null, body };
}

/** `stats` polls /generation for the real cost (up to 21 s); off once the probe shows TTS generations are not listed there. */
export async function synthesize(p: TtsPaths, sink: CallSink, clip: SpokenClip, stats = true): Promise<TtsRow> {
	const pcm = join(p.ttsDir, `${clip.id}.pcm`);
	const body = JSON.stringify({
		model: TTS_MODEL,
		input: clip.text.spoken,
		voice: clip.voice,
		instructions: TTS_STYLE,
		// Gemini TTS rejects mp3 (400 on 2026-10-16): "only supports response_format=\"pcm\"".
		response_format: "pcm",
	});
	return loggedCall(sink, async (attempt) => {
		const startedAt = new Date().toISOString();
		const t0 = performance.now();
		let status = 0;
		let contentType: string | null = null;
		let generationId: string | null = null;
		let retryAfterSec: number | null = null;
		let error: string | undefined;
		try {
			const res = await fetch(`${API}/audio/speech`, {
				method: "POST",
				headers: authHeaders(),
				body,
				signal: AbortSignal.timeout(120_000),
			});
			status = res.status;
			contentType = res.headers.get("content-type");
			generationId = res.headers.get("x-generation-id");
			retryAfterSec = retryAfter(res);
			if (res.ok) await Bun.write(pcm, res);
			else error = (await res.text()).slice(0, 500);
		} catch (e) {
			error = String(e);
		}
		const latencyMs = performance.now() - t0;
		let audioSec = 0;
		if (status === 200 && !error) {
			try {
				await $`ffmpeg -hide_banner -loglevel error -y -f s16le -ar ${PCM_RATE} -ac 1 -i ${pcm} -c:a pcm_s16le ${clip.wavPath}`;
				audioSec = await durationSec(clip.wavPath);
			} catch (e) {
				error = `decode failed: ${String(e).slice(0, 300)}`;
			}
		}
		const ok = status === 200 && !error && audioSec >= 1;
		const gen = stats && generationId && status === 200 ? await generationStats(generationId) : { cost: null, body: null };
		const estimate = status === 200 ? estimateUsd(audioSec, clip.text.spoken.length) : null;
		const row: TtsRow = {
			kind: "tts",
			model: TTS_MODEL,
			voice: clip.voice,
			clipId: clip.id,
			attempt,
			startedAt,
			status,
			ok,
			latencyMs,
			contentType,
			audioBytes: status === 200 ? Bun.file(pcm).size : 0,
			audioSec,
			inputChars: clip.text.spoken.length,
			cost: gen.cost ?? estimate,
			costSource: gen.cost !== null ? "generation" : estimate !== null ? "estimate" : null,
			generationId,
			generation: gen.body,
			...(error ? { error } : !ok ? { error: `audio too short: ${audioSec} s` } : {}),
		};
		return { row, retryAfterSec };
	});
}

/** Clip ids with a successful TTS row and a WAV on disk. */
export async function synthesized(p: TtsPaths, clips: SpokenClip[]): Promise<Set<string>> {
	const ok = new Set((await readJsonl<TtsRow>(p.ttsRaw)).filter((r) => r.ok).map((r) => r.clipId));
	const done = new Set<string>();
	for (const c of clips) if (ok.has(c.id) && (await Bun.file(c.wavPath).exists())) done.add(c.id);
	return done;
}

/**
 * Synthesizes every clip without a successful row (resume-safe). The first
 * clip runs alone; the rest start only when their projected cost fits the cap.
 */
export async function runTts(
	p: TtsPaths,
	clips: SpokenClip[],
	budget: Budget,
	concurrency: number,
	dryRun: boolean,
): Promise<void> {
	const done = await synthesized(p, clips);
	const pending = clips.filter((c) => !done.has(c.id));
	const sec = pending.reduce((s, c) => s + plannedSec(c), 0);
	const usd = pending.reduce((s, c) => s + plannedUsd(c), 0);
	console.log(
		`\nTTS: ${TTS_MODEL}, voices ${VOICES.join(", ")}: done ${done.size}, pending ${pending.length}, ` +
			`~${(sec / 60).toFixed(1)} min audio, ~$${usd.toFixed(3)} at listed price`,
	);
	if (dryRun || !pending.length || budget.exceeded) return;
	await mkdir(p.ttsDir, { recursive: true });
	await mkdir(p.clips, { recursive: true });
	const sink = { out: p.ttsRaw, budget };

	// First clip alone: catches a rejected voice or format and measures the real price before the pool.
	const [first, ...rest] = pending;
	const probe = await synthesize(p, sink, first!);
	if (probe.status === 401 || probe.status === 402) throw new Error(`OpenRouter returned ${probe.status}: ${probe.error}`);
	if (!probe.ok) throw new Error(`TTS probe failed on ${first!.id}: ${probe.status} ${probe.error ?? ""}`);
	const usdPerSec = (probe.cost ?? 0) / probe.audioSec;
	const projected = rest.reduce((s, c) => s + plannedSec(c), 0) * Math.max(usdPerSec, USD_PER_AUDIO_SEC);
	console.log(
		`  probe ${first!.id}: ${probe.audioSec.toFixed(1)} s audio, $${(probe.cost ?? 0).toFixed(5)} (${probe.costSource}), ` +
			`projected $${projected.toFixed(3)} for the rest`,
	);
	if (budget.total + projected > budget.cap) {
		console.error(`  TTS stopped: projected $${projected.toFixed(3)} would pass the $${budget.cap.toFixed(2)} cap`);
		return;
	}
	await runCalls("tts", rest, concurrency, budget, (c) => synthesize(p, sink, c, probe.costSource === "generation"), (c) => c.id);
}
