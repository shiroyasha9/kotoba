// Latency probe: where does the time between the last body byte and the answer go, and which request shape is fastest?
// bun run latency --exp duration|shape|hedge|models|idle|primer|spacing|long|formats|codec|segments|hedgecold|score
//   [--clips N] [--repeat N] [--models SLUG,SLUG] [--zdr] [--cap USD] [--dry-run] [--data DIR] [--out DIR]
// Requests go one at a time (a hedge pair goes as two at once), with the variant order rotated per clip, so variants
// share the time of day. Every attempt is appended to `<out>/results/latency-raw.jsonl` as it completes; `--exp report`
// prints p50/p90 per experiment and variant from that file only.
// `--data` is the kotoba-bench-v1 folder (its 16 kHz FLACs and dictionary); `--out` holds this probe's trimmed audio and
// raw rows.

import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { $ } from "bun";
import { fail, intArg } from "../cli.ts";
import {
	type AudioInfo,
	type Clip,
	audioPath,
	dictionaryTerms,
	loadClips,
	loadDictionary,
	loadReferences,
	paths,
	seededSample,
} from "../data.ts";
import { API, Budget, appendJsonl, authHeaders, readJsonl, spentUsd } from "../openrouter.ts";
import { fmtMs, percentile, score } from "../report.ts";
import { LISTED_USD_PER_SEC, MAI, biasTerms } from "../stt.ts";

/** Default cap on this probe's raw file, across runs. */
const COST_CAP_USD = 0.5;
const EXPERIMENTS = [
	"duration",
	"shape",
	"hedge",
	"models",
	"idle",
	"primer",
	"spacing",
	"long",
	"formats",
	"codec",
	"segments",
	"hedgecold",
	"coldcodec",
	"report",
	"score",
] as const;
type Experiment = (typeof EXPERIMENTS)[number];
/** Trim lengths for the duration sweep, in seconds. */
const DURATIONS = [3, 6, 10, 15, 20, 30];
/** Trim lengths for the long sweep (one clip of 60 s or more), in seconds. */
const LONG_DURATIONS = [15, 30, 45, 60];
/** The segments experiment: a segment ends at the first pause after this much audio, as an upload during the recording. */
const SEGMENT_SEC = 15;
/** The hedgecold experiment: quiet time before each set (the app counts a route cold after 40 s), and the recording. */
const HEDGE_QUIET_SEC = 65;
const HEDGE_RECORDING_SEC = 12;
/** Container per file extension, as `input_audio.format`. */
const FORMATS: Record<string, string> = { flac: "flac", wav: "wav", ogg: "ogg", webm: "webm", m4a: "m4a", mp3: "mp3" };
/** The idle experiment: quiet time before a cold request, and the gaps between a small request and the measured one. */
const IDLE_SEC = 90;
const GAPS_SEC = [3, 15, 45];
/** The primer experiment: the time from a primer (sent at key-down) to the measured request (sent at the stop). */
const RECORDING_SEC = 10;
/** The spacing experiment: time from the primer's answer to the first clip, as in a dictation of that length. */
const SPACINGS_SEC = [2, 10, 25];
const PRIMER_AUDIO =
	"ZkxhQwAAACIQABAAAAALAAANA+gA8AAAH0Ae4Bk2cWCcfWPP6JuSCtMThAAAKCAAAAByZWZlcmVuY2UgbGliRkxBQyAxLjUuMCAyMDI1" +
	"MDIxMQAAAAD/+MUIAG8AAABlVf/4dQgBDz/iAAAAZoI=";

const { values } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		exp: { type: "string" },
		clips: { type: "string", default: "10" },
		repeat: { type: "string", default: "3" },
		models: { type: "string" },
		// Rounds at once: for a quality pass (WER) only, as their times contend for one uplink.
		parallel: { type: "string", default: "1" },
		// The codec experiment: the clip lengths and the codecs to compare with the app's FLAC.
		min: { type: "string", default: "10" },
		max: { type: "string", default: "20" },
		codecs: { type: "string", default: "opus24,opus16" },
		// The models experiment: every model only on zero-data-retention endpoints (as the app sends MAI).
		zdr: { type: "boolean", default: false },
		// The primer experiment: which primers to compare (default all of PRIMERS).
		primers: { type: "string" },
		// The spacing experiment: which sets to run (default all: none, gap<N> for each spacing, double10).
		sets: { type: "string" },
		cap: { type: "string" },
		"dry-run": { type: "boolean", default: false },
		data: { type: "string", default: Bun.env.KOTOBA_BENCH_DATA },
		out: { type: "string", default: Bun.env.KOTOBA_LATENCY_DATA },
	},
});

const exp = values.exp as Experiment | undefined;
if (!exp || !EXPERIMENTS.includes(exp)) fail(`--exp must be one of ${EXPERIMENTS.join(", ")}`);
if (!values.data) fail("set KOTOBA_BENCH_DATA or pass --data DIR");
if (!values.out) fail("set KOTOBA_LATENCY_DATA or pass --out DIR");
const clipCount = intArg(values, "clips", 1)!;
const repeat = intArg(values, "repeat", 1)!;
const parallel = intArg(values, "parallel", 1)!;
const runCap = values.cap === undefined ? undefined : Number(values.cap);
if (runCap !== undefined && !(runCap > 0)) fail("--cap must be a positive number of USD");

const p = paths(values.data);
const out = values.out;
const raw = join(out, "results", "latency-raw.jsonl");

/** One request shape. `json` is what kotoba sends today (`OpenRouterProvider`): base64 FLAC in JSON, ZDR, phrase list. */
type Variant = {
	key: string;
	model: string;
	body: "json" | "multipart";
	zdr: boolean;
	phrases: boolean;
	/** A free primer instead of a transcription: `GET /key`, or a transcription POST with an empty JSON object. */
	free?: "key" | "empty";
};

type Job = {
	exp: Experiment;
	variant: Variant;
	clipId: string;
	file: string;
	durationSec: number;
	pair?: string;
	/** Seconds with no request before this one's round starts. */
	idleBefore?: number;
	/** Milliseconds after its round starts before this request goes, so two requests of a round overlap in time. */
	delayMs?: number;
	/** Starts when the job before it in the round answered ("previous"), or every job before it ("all"); then `delayMs`. */
	after?: "previous" | "all";
	segment?: Row["segment"];
};

type Row = {
	exp: Experiment;
	variant: string;
	model: string;
	clipId: string;
	pair: string | null;
	startedAt: string;
	durationSec: number;
	bodyBytes: number;
	status: number;
	ok: boolean;
	/** Request start to response headers (the answer's first byte), and to the end of the body. */
	headersMs: number;
	doneMs: number;
	cost: number | null;
	generationId: string | null;
	/** Response headers that may name the edge or the upstream (cf-ray, server, x-*). */
	headers: Record<string, string>;
	textLength: number | null;
	/** The transcript, for the WER of a request shape (`--exp score`). Rows before 2026-10-19 have none. */
	text?: string | null;
	/** A segment of a longer clip (`--exp segments`): its index from 0, the count, and where it starts. */
	segment?: { index: number; count: number; startSec: number };
	error?: string;
};

const terms = biasTerms(await loadDictionary(p));

function variant(key: string, model: string, over: Partial<Variant> = {}): Variant {
	return { key, model, body: "json", zdr: model === MAI || values.zdr, phrases: model === MAI, ...over };
}

const APP = variant("app", MAI);

async function body(v: Variant, file: string): Promise<{ url: string; init: RequestInit; bytes: number }> {
	const headers = authHeaders();
	const Authorization = headers.Authorization!;
	const url = `${API}/audio/transcriptions`;
	if (v.free === "key") return { url: `${API}/key`, init: { headers: { Authorization } }, bytes: 0 };
	if (v.free === "empty") {
		return { url, init: { method: "POST", headers, body: "{}" }, bytes: 2 };
	}
	const audio = await Bun.file(file).bytes();
	const provider = {
		...(v.zdr ? { zdr: true } : {}),
		...(v.phrases ? { options: { azure: { phraseList: { phrases: terms } } } } : {}),
	};
	if (v.body === "multipart") {
		const form = new FormData();
		form.append("file", new Blob([audio], { type: "audio/flac" }), "audio.flac");
		form.append("model", v.model);
		form.append("language", "en");
		if (Object.keys(provider).length) form.append("provider", JSON.stringify(provider));
		return { url, init: { method: "POST", headers: { Authorization }, body: form }, bytes: audio.byteLength };
	}
	const json = JSON.stringify({
		input_audio: { format: FORMATS[file.split(".").pop() ?? ""] ?? "flac", data: audio.toBase64() },
		model: v.model,
		language: "en",
		...(Object.keys(provider).length ? { provider } : {}),
	});
	return {
		url,
		init: { method: "POST", headers, body: json },
		bytes: json.length,
	};
}

/** One attempt, no retry: a retry would hide the latency the app sees. */
async function send(job: Job): Promise<Row> {
	if (job.delayMs) await Bun.sleep(job.delayMs);
	const { url, init, bytes } = await body(job.variant, job.file);
	const startedAt = new Date().toISOString();
	const t0 = performance.now();
	let headersMs = -1;
	let status = 0;
	let parsed: { text?: string; usage?: { cost?: number } } | null = null;
	let error: string | undefined;
	let generationId: string | null = null;
	const headers: Record<string, string> = {};
	try {
		const res = await fetch(url, { ...init, signal: AbortSignal.timeout(90_000) });
		headersMs = performance.now() - t0;
		status = res.status;
		generationId = res.headers.get("x-generation-id");
		res.headers.forEach((value, name) => {
			if (name === "cf-ray" || name === "server" || name.startsWith("x-") || name.includes("timing")) headers[name] = value;
		});
		const text = await res.text();
		try {
			parsed = JSON.parse(text);
		} catch {
			error = text.slice(0, 300);
		}
		if (!res.ok) error = text.slice(0, 300);
	} catch (e) {
		error = String(e);
	}
	const row: Row = {
		exp: job.exp,
		variant: job.variant.key,
		model: job.variant.model,
		clipId: job.clipId,
		pair: job.pair ?? null,
		startedAt,
		durationSec: job.durationSec,
		bodyBytes: bytes,
		status,
		ok: status === 200 && typeof parsed?.text === "string",
		headersMs,
		doneMs: performance.now() - t0,
		cost: parsed?.usage?.cost ?? null,
		generationId,
		headers,
		textLength: parsed?.text?.length ?? null,
		text: parsed?.text ?? null,
		...(job.segment ? { segment: job.segment } : {}),
		...(error ? { error } : {}),
	};
	await appendJsonl(raw, row);
	return row;
}

/** Rotates `items` by `i`, so each variant takes each position in turn. */
const rotate = <T>(items: T[], i: number) => [...items.slice(i % items.length), ...items.slice(0, i % items.length)];

/** The kotoba-bench-v1 clips of `min`-`max` seconds, seeded. */
async function pick(min: number, max: number, n: number): Promise<AudioInfo[]> {
	const index = await readJsonl<AudioInfo>(p.audioIndex);
	return seededSample(
		index.filter((a) => a.durationSec >= min && a.durationSec <= max).sort((a, b) => a.clipId.localeCompare(b.clipId)),
		n,
	);
}

/** The first `seconds` of a clip, as 16 kHz mono FLAC in `<out>/audio`. */
async function trimmed(clipId: string, seconds: number): Promise<string> {
	const dir = join(out, "audio");
	await mkdir(dir, { recursive: true });
	const file = join(dir, `${clipId}.${seconds}s.flac`);
	if (!(await Bun.file(file).exists())) {
		await $`ffmpeg -hide_banner -loglevel error -y -i ${audioPath(p, clipId, "flac")} -t ${seconds} -c:a flac ${file}`;
	}
	return file;
}

/** Encoder settings per lossy shape: the bench FLAC re-encoded, mono 16 kHz, so only the codec changes. */
const CODECS: Record<string, { ext: string; args: string[] }> = {
	opus32: { ext: "ogg", args: ["-c:a", "libopus", "-b:a", "32k", "-application", "voip"] },
	opus24: { ext: "ogg", args: ["-c:a", "libopus", "-b:a", "24k", "-application", "voip"] },
	opus16: { ext: "ogg", args: ["-c:a", "libopus", "-b:a", "16k", "-application", "voip"] },
	webm24: { ext: "webm", args: ["-c:a", "libopus", "-b:a", "24k", "-application", "voip"] },
	aac32: { ext: "m4a", args: ["-c:a", "aac_at", "-b:a", "32k"] },
	mp332: { ext: "mp3", args: ["-c:a", "libmp3lame", "-b:a", "32k"] },
	wav: { ext: "wav", args: ["-c:a", "pcm_s16le"] },
	// Apple's Opus encoder at 24 kbps in kotoba's own Ogg framing, as the app would upload: no ffmpeg settings, the files
	// are made before the run (`<runbooks>/2026-10-19-kotoba-latency-2/run.log`).
	apple24: { ext: "ogg", args: [] },
};

/** A clip in another codec, in `<out>/audio`. */
async function encoded(clipId: string, codec: string): Promise<string> {
	const { ext, args } = CODECS[codec]!;
	const dir = join(out, "audio");
	await mkdir(dir, { recursive: true });
	const file = join(dir, `${clipId}.${codec}.${ext}`);
	if (!(await Bun.file(file).exists())) {
		if (!args.length) fail(`${file} is made outside this probe`);
		await $`ffmpeg -hide_banner -loglevel error -y -i ${audioPath(p, clipId, "flac")} -ac 1 -ar 16000 ${args} ${file}`;
	}
	return file;
}

/** Where a recording split at pauses would cut: the middle of the first pause of 0.4 s or more (under -40 dB) that starts
 * `SEGMENT_SEC` or more after the last cut. An app that uploads during the recording cuts at such a pause. */
async function cuts(file: string, durationSec: number): Promise<number[]> {
	const log = await $`ffmpeg -hide_banner -nostats -i ${file} -af silencedetect=noise=-40dB:d=0.4 -f null -`.quiet().nothrow();
	const text = log.stderr.toString();
	const starts = [...text.matchAll(/silence_start: ([\d.]+)/g)].map((m) => Number(m[1]));
	const ends = [...text.matchAll(/silence_end: ([\d.]+)/g)].map((m) => Number(m[1]));
	const out: number[] = [];
	let last = 0;
	starts.forEach((start, i) => {
		const end = ends[i] ?? durationSec;
		// A cut in the last 2 s would leave a segment too short to test the tail.
		if (start - last >= SEGMENT_SEC && end < durationSec - 2) {
			// On a 10 ms grid: ffmpeg's FLAC encoder fails on a cut that leaves a first frame of a few samples.
			const cut = Math.round((start + end) * 50) / 100;
			out.push(cut);
			last = cut;
		}
	});
	return out;
}

/** Seconds `from`-`to` of a clip, as 16 kHz mono FLAC in `<out>/audio`. */
async function piece(clipId: string, from: number, to: number | null): Promise<string> {
	const dir = join(out, "audio");
	await mkdir(dir, { recursive: true });
	const file = join(dir, `${clipId}.seg-${from.toFixed(2)}-${to === null ? "end" : to.toFixed(2)}.flac`);
	// A failed encode leaves an empty file: make it again.
	if (!(await Bun.file(file).exists()) || Bun.file(file).size === 0) {
		// Output seeking (after -i) decodes up to the cut, so no piece starts with a partial FLAC frame.
		const end = to === null ? [] : ["-to", String(to)];
		await $`ffmpeg -hide_banner -loglevel error -y -i ${audioPath(p, clipId, "flac")} -ss ${from} ${end} -c:a flac ${file}`.catch((e) => fail(`${file}: ${e}`));
	}
	return file;
}

async function plan(): Promise<Job[][]> {
	switch (exp) {
		case "duration": {
			// One long clip, cut to each length: the same voice and room, so only the length changes.
			const [clip] = await pick(32, 40, 1);
			if (!clip) fail("no 32-40 s clip in the bench data");
			const lengths = await Promise.all(DURATIONS.map(async (s) => ({ s, file: await trimmed(clip.clipId, s) })));
			return Array.from({ length: repeat }, (_, r) =>
				rotate(lengths, r).map(({ s, file }) => [
					{ exp, variant: { ...APP, key: `app-${s}s` }, clipId: clip.clipId, file, durationSec: s },
				]),
			).flat();
		}
		case "shape":
		case "models": {
			const variants =
				exp === "shape"
					? [APP, variant("bare", MAI, { zdr: false, phrases: false }), variant("multipart", MAI, { body: "multipart" })]
					: [APP, ...(values.models ?? "").split(",").filter(Boolean).map((m) => variant(m, m))];
			if (variants.length < 2) fail("--exp models needs --models SLUG,SLUG");
			const clips = await pick(10, 20, clipCount);
			return clips.flatMap((c, i) =>
				rotate(variants, i).map((v) => [
					{ exp, variant: v, clipId: c.clipId, file: audioPath(p, c.clipId, "flac"), durationSec: c.durationSec },
				]),
			);
		}
		case "hedge": {
			// Two identical requests at once: if their times are not correlated, the faster one cuts the tail.
			const clips = await pick(10, 20, clipCount);
			return clips.map((c) =>
				["a", "b"].map((side) => ({
					exp,
					variant: { ...APP, key: `app-${side}` },
					clipId: c.clipId,
					file: audioPath(p, c.clipId, "flac"),
					durationSec: c.durationSec,
					pair: c.clipId,
				})),
			);
		}
		case "idle": {
			// Does the time since the last request decide the server time? After `IDLE_SEC` quiet, a 3 s request (cold),
			// then after each gap a 10-20 s request: the app's dictations come minutes apart, the other probes back to back.
			const [clip] = await pick(10, 20, 1);
			if (!clip) fail("no 10-20 s clip in the bench data");
			const small = await trimmed(clip.clipId, 3);
			const full = audioPath(p, clip.clipId, "flac");
			return Array.from({ length: repeat }, (_, r) => rotate(GAPS_SEC, r))
				.flat()
				.flatMap((gap) => [
					[{ exp, variant: { ...APP, key: "cold-3s" }, clipId: clip.clipId, file: small, durationSec: 3, idleBefore: IDLE_SEC }],
					[{ exp, variant: { ...APP, key: `after-${gap}s` }, clipId: clip.clipId, file: full, durationSec: clip.durationSec, idleBefore: gap }],
				]);
		}
		case "primer": {
			// Which request at key-down warms the path for the transcription at the stop? Each set starts cold
			// (`IDLE_SEC` quiet), sends a primer, waits `RECORDING_SEC`, then sends a 10-20 s clip.
			const [clip] = await pick(10, 20, 1);
			if (!clip) fail("no 10-20 s clip in the bench data");
			const full = audioPath(p, clip.clipId, "flac");
			const silence = join(out, "audio", "silence-0.5s.flac");
			await mkdir(join(out, "audio"), { recursive: true });
			// The app's primer audio (`OpenRouterProvider.primerAudio`), so the probe sends the same bytes.
			await Bun.write(silence, Buffer.from(PRIMER_AUDIO, "base64"));
			const all: Record<string, Variant | null> = {
				none: null,
				key: { ...APP, key: "primer-key", free: "key" },
				empty: { ...APP, key: "primer-empty", free: "empty" },
				silence: { ...APP, key: "primer-silence" },
				// Silence with the route's ZDR but no phrase list: what the app's primer sends.
				bare: { ...APP, key: "primer-bare", phrases: false },
			};
			const names = values.primers?.split(",") ?? Object.keys(all);
			const unknown = names.filter((n) => !(n in all));
			if (unknown.length) fail(`--primers takes ${Object.keys(all).join(", ")}; not ${unknown.join(", ")}`);
			const primers = names.map((n) => all[n]!);
			const measured = (after: string, idleBefore: number): Job => ({
				exp, variant: { ...APP, key: `after-${after}` }, clipId: clip.clipId, file: full, durationSec: clip.durationSec, idleBefore,
			});
			return Array.from({ length: repeat }, (_, r) => rotate(primers, r))
				.flat()
				.flatMap((primer) =>
					primer
						? [
								[{ exp, variant: primer, clipId: "silence", file: silence, durationSec: primer.free ? 0 : 0.5, idleBefore: IDLE_SEC }],
								[measured(primer.key.replace("primer-", ""), RECORDING_SEC)],
							]
						: [[measured("none", IDLE_SEC)]],
				);
		}
		case "spacing": {
			// Is a primed clip slower than a warm one? After `IDLE_SEC` quiet: no primer, or the app's primer and a gap;
			// then the same 10-20 s clip three times back to back (A, B, C). B and C are the warm reference.
			const [clip] = await pick(10, 20, 1);
			if (!clip) fail("no 10-20 s clip in the bench data");
			const full = audioPath(p, clip.clipId, "flac");
			const silence = join(out, "audio", "silence-0.5s.flac");
			await mkdir(join(out, "audio"), { recursive: true });
			await Bun.write(silence, Buffer.from(PRIMER_AUDIO, "base64"));
			const clipRun = (set: string, idleBefore: number): Job[][] =>
				["A", "B", "C"].map((n, i) => [
					{
						exp,
						variant: { ...APP, key: `${set}-${n}` },
						clipId: clip.clipId,
						file: full,
						durationSec: clip.durationSec,
						idleBefore: i ? 0 : idleBefore,
					},
				]);
			const primer = (set: string, idleBefore: number): Job[] => [
				{ exp, variant: { ...APP, key: `${set}-primer`, phrases: false }, clipId: "silence", file: silence, durationSec: 0.5, idleBefore },
			];
			const all: Record<string, Job[][]> = {
				none: clipRun("none", IDLE_SEC),
				...Object.fromEntries(SPACINGS_SEC.map((gap) => [`gap${gap}`, [primer(`gap${gap}`, IDLE_SEC), ...clipRun(`gap${gap}`, gap)]])),
				// Two primers one after the other, then the clip 10 s after the second answer.
				double10: [primer("double10", IDLE_SEC), primer("double10", 0), ...clipRun("double10", 10)],
				// Size or speech? White noise of the clip's size and length, a 1 s body as large (48 kHz stereo), and the first
				// 3 s of the clip (speech, a small body). Each file is made in `<out>/audio` before the run (run.log).
				...Object.fromEntries(
					[
						["noise15", join(out, "audio", "noise-15s-16k.flac"), 15],
						["noise1big", join(out, "audio", "noise-1s-48k.flac"), 1],
						["noise1full", join(out, "audio", "noise-1s-48k-full.flac"), 1],
						["noise1wav", join(out, "audio", "noise-1s-48k-s32.wav"), 1],
						// The app's large primer (`OpenRouterPrimer.noiseWAV`), written by the same SplitMix64 steps.
						["appwav", join(out, "audio", "noise-1s-app.wav"), 1],
						["speech3", join(out, "audio", `${clip.clipId}.3s.flac`), 3],
					].map(([set, file, sec]) => [
						set as string,
						[
							[{ exp, variant: { ...APP, key: `${set}-primer`, phrases: false }, clipId: "primer", file: file as string, durationSec: sec as number, idleBefore: IDLE_SEC }],
							...clipRun(set as string, 10),
						],
					]),
				),
				// The clip itself as the primer: does a full-size body warm what the silent primer does not?
				// A primer still on its way at the stop: a 3 s clip goes 2 s after the primer. Bun's fetch may open a second
				// connection for it, where the app multiplexes both on one HTTP/2 connection: the app-like measure is the
				// URLSession probe in `<runbooks>/2026-10-17-kotoba-latency/inflight/`.
				...Object.fromEntries(
					(
						[
							["inflight-large", join(out, "audio", "noise-1s-app.wav"), 1],
							["inflight-silent", silence, 0.5],
							["inflight-none", null, 0],
						] as const
					).map(([set, file, sec]) => [
						set,
						[
							[
								...(file
									? [{ exp, variant: { ...APP, key: `${set}-primer`, phrases: false }, clipId: "primer", file, durationSec: sec, idleBefore: IDLE_SEC }]
									: []),
								{
									exp,
									variant: { ...APP, key: `${set}-clip` },
									clipId: clip.clipId,
									file: join(out, "audio", `${clip.clipId}.3s.flac`),
									durationSec: 3,
									idleBefore: IDLE_SEC,
									delayMs: file ? 2000 : 0,
								},
							],
						],
					]),
				),
				clip10: [
					[{ exp, variant: { ...APP, key: "clip10-primer", phrases: false }, clipId: clip.clipId, file: full, durationSec: clip.durationSec, idleBefore: IDLE_SEC }],
					...clipRun("clip10", 10),
				],
			};
			const names = values.sets?.split(",") ?? Object.keys(all);
			const unknown = names.filter((n) => !(n in all));
			if (unknown.length) fail(`--sets takes ${Object.keys(all).join(", ")}; not ${unknown.join(", ")}`);
			const sets = names.map((n) => all[n]!);
			return Array.from({ length: repeat }, (_, r) => rotate(sets, r)).flat(2);
		}
		case "long": {
			// Does the server time keep its 10 ms per audio second past 30 s? One 60 s+ clip cut to each length, warm.
			const [clip] = await pick(62, 120, 1);
			if (!clip) fail("no 62-120 s clip in the bench data");
			const lengths = await Promise.all(LONG_DURATIONS.map(async (s) => ({ s, file: await trimmed(clip.clipId, s) })));
			return Array.from({ length: repeat }, (_, r) =>
				rotate(lengths, r).map(({ s, file }) => [
					{ exp, variant: { ...APP, key: `app-${s}s` }, clipId: clip.clipId, file, durationSec: s },
				]),
			).flat();
		}
		case "formats": {
			// Which containers does the route take? One short clip in each.
			const [clip] = await pick(4, 6, 1);
			if (!clip) fail("no 4-6 s clip in the bench data");
			const files = [["flac", audioPath(p, clip.clipId, "flac")], ...(await Promise.all(Object.keys(CODECS).map(async (c) => [c, await encoded(clip.clipId, c)])))];
			return files.map(([key, file]) => [{ exp, variant: { ...APP, key: key! }, clipId: clip.clipId, file: file!, durationSec: clip.durationSec }]);
		}
		case "codec": {
			// A smaller body: FLAC (the app) against Opus in Ogg, the same clips, the order rotated. WER: `--exp score`.
			const codecs = values.codecs.split(",");
			const unknown = codecs.filter((c) => !(c in CODECS));
			if (unknown.length) fail(`--codecs takes ${Object.keys(CODECS).join(", ")}; not ${unknown.join(", ")}`);
			const clips = await pick(Number(values.min), Number(values.max), clipCount);
			return Promise.all(
				clips.map(async (c, i) => {
					const files = [
						{ v: APP, file: audioPath(p, c.clipId, "flac") },
						...(await Promise.all(codecs.map(async (k) => ({ v: { ...APP, key: k }, file: await encoded(c.clipId, k) })))),
					];
					return rotate(files, i).map(({ v, file }) => [{ exp, variant: v, clipId: c.clipId, file, durationSec: c.durationSec }]);
				}),
			).then((r) => r.flat());
		}
		case "segments": {
			// Upload during the recording: a long clip whole, then as the segments a pause-split upload would send, one after
			// the other (warm). The last segment's time is what would be left after the stop. WER: `--exp score`.
			const clips = await pick(40, 120, clipCount);
			const rounds: Job[][] = [];
			for (const c of clips) {
				const at = await cuts(audioPath(p, c.clipId, "flac"), c.durationSec);
				if (!at.length) continue;
				const bounds = [0, ...at];
				rounds.push([{ exp, variant: { ...APP, key: "whole" }, clipId: c.clipId, file: audioPath(p, c.clipId, "flac"), durationSec: c.durationSec }]);
				for (const [i, from] of bounds.entries()) {
					const to = bounds[i + 1] ?? null;
					rounds.push([
						{
							exp,
							variant: { ...APP, key: i === bounds.length - 1 ? "segment-last" : "segment" },
							clipId: c.clipId,
							file: await piece(c.clipId, from, to),
							durationSec: (to ?? c.durationSec) - from,
							segment: { index: i, count: bounds.length, startSec: from },
						},
					]);
				}
			}
			return rounds;
		}
		case "hedgecold": {
			// The app's cold path, then the same request twice at once: after `HEDGE_QUIET_SEC` quiet the silent primer, the
			// large one when it answered, and `HEDGE_RECORDING_SEC` after the silent one the clip as two requests (A, B), then
			// once more (C, the warm reference). Is a cold spike in one of a pair also in the other?
			const clips = await pick(10, 20, clipCount);
			const silence = join(out, "audio", "silence-0.5s.flac");
			await mkdir(join(out, "audio"), { recursive: true });
			await Bun.write(silence, Buffer.from(PRIMER_AUDIO, "base64"));
			const large = join(out, "audio", "noise-1s-app.wav");
			if (!(await Bun.file(large).exists())) fail(`copy the app's large primer to ${large}`);
			const run = Date.now().toString(36);
			return clips.map((c, i) => {
				const clip = (key: string, delayMs: number, pair: string | undefined, after?: Job["after"]): Job => ({
					exp, variant: { ...APP, key }, clipId: c.clipId, file: audioPath(p, c.clipId, "flac"), durationSec: c.durationSec, pair, delayMs, after,
				});
				return [
					{ exp, variant: { ...APP, key: "primer-silent", phrases: false }, clipId: "primer", file: silence, durationSec: 0.5, idleBefore: HEDGE_QUIET_SEC },
					{ exp, variant: { ...APP, key: "primer-large", phrases: false }, clipId: "primer", file: large, durationSec: 1, after: "previous" },
					clip("A", HEDGE_RECORDING_SEC * 1000, `${run}-${i}`),
					clip("B", HEDGE_RECORDING_SEC * 1000, `${run}-${i}`),
					clip("C", 0, undefined, "all"),
				];
			});
		}
		case "coldcodec": {
			// The app's cold path as in hedgecold, then one request: the app's FLAC or Apple's Opus (`apple24`), alternating
			// per set. The FLAC sets are also the single-request control for hedgecold.
			const clips = await pick(10, 20, clipCount);
			const silence = join(out, "audio", "silence-0.5s.flac");
			await mkdir(join(out, "audio"), { recursive: true });
			await Bun.write(silence, Buffer.from(PRIMER_AUDIO, "base64"));
			const large = join(out, "audio", "noise-1s-app.wav");
			if (!(await Bun.file(large).exists())) fail(`copy the app's large primer to ${large}`);
			return Promise.all(
				clips.map(async (c, i) => {
					const opus = i % 2 === 1;
					const file = opus ? await encoded(c.clipId, "apple24") : audioPath(p, c.clipId, "flac");
					return [
						{ exp, variant: { ...APP, key: "primer-silent", phrases: false }, clipId: "primer", file: silence, durationSec: 0.5, idleBefore: HEDGE_QUIET_SEC },
						{ exp, variant: { ...APP, key: "primer-large", phrases: false }, clipId: "primer", file: large, durationSec: 1, after: "previous" },
						{ exp, variant: { ...APP, key: opus ? "apple24" : "app" }, clipId: c.clipId, file, durationSec: c.durationSec, delayMs: HEDGE_RECORDING_SEC * 1000 },
					] satisfies Job[];
				}),
			);
		}
		default:
			return [];
	}
}

async function report(): Promise<void> {
	const rows = await readJsonl<Row>(raw);
	const groups = new Map<string, Row[]>();
	for (const r of rows) groups.set(`${r.exp} ${r.variant}`, [...(groups.get(`${r.exp} ${r.variant}`) ?? []), r]);
	for (const [key, list] of [...groups].sort(([a], [b]) => a.localeCompare(b, "en", { numeric: true }))) {
		const ok = list.filter((r) => r.ok);
		const ms = ok.map((r) => r.headersMs);
		const bytes = Math.round(ok.reduce((s, r) => s + r.bodyBytes, 0) / Math.max(1, ok.length) / 1024);
		const line = ms.length ? `p50 ${fmtMs(percentile(ms, 0.5))} ms, p90 ${fmtMs(percentile(ms, 0.9))} ms, min ${fmtMs(Math.min(...ms))}` : "no answer";
		console.log(`${key}: ${ok.length}/${list.length} ok, ${line}, body ${bytes} KiB`);
	}
	// A hedge pair counts as the faster of its two answers.
	const pairs = new Map<string, number[]>();
	for (const name of ["hedge", "hedgecold"] as const) {
		pairs.clear();
		for (const r of rows) {
			if (r.exp !== name || !r.ok || !r.pair) continue;
			const key = name === "hedge" ? `${r.pair} ${r.startedAt.slice(0, 16)}` : r.pair;
			pairs.set(key, [...(pairs.get(key) ?? []), r.headersMs]);
		}
		const best = [...pairs.values()].filter((v) => v.length === 2).map((v) => Math.min(...v));
		if (best.length) console.log(`${name} faster-of-two: ${best.length} pairs, p50 ${fmtMs(percentile(best, 0.5))} ms, p90 ${fmtMs(percentile(best, 0.9))} ms, max ${fmtMs(Math.max(...best))}`);
	}
	console.log(`spent in ${raw}: $${(await spentUsd([raw])).toFixed(4)}`);
}

/** WER and term recall per experiment and variant, on the clips every variant of the experiment answered. A segmented
 * clip counts as its segments' texts joined in order. */
async function scoreRows(): Promise<void> {
	const rows = (await readJsonl<Row>(raw)).filter((r) => r.ok && typeof r.text === "string" && r.clipId !== "primer");
	const { clips } = await loadClips(p);
	const owner = await loadReferences(p);
	const byId = new Map(clips.map((c) => [c.id, c]));
	const ref = (c: Clip) => owner.get(c.id)?.text ?? c.reference;
	const terms = dictionaryTerms(await loadDictionary(p));
	for (const name of ["codec", "models", "formats", "segments"] as const) {
		const texts = new Map<string, Map<string, string>>();
		const put = (v: string, id: string, t: string) => texts.set(v, (texts.get(v) ?? new Map()).set(id, t));
		const mine = rows.filter((r) => r.exp === name);
		if (!mine.length) continue;
		if (name === "segments") {
			for (const r of mine) if (r.variant === "whole") put("whole", r.clipId, r.text!);
			const parts = new Map<string, Row[]>();
			for (const r of mine) if (r.segment) parts.set(r.clipId, [...(parts.get(r.clipId) ?? []), r]);
			for (const [id, list] of parts) {
				const seen = new Map(list.map((r) => [r.segment!.index, r]));
				const count = list[0]!.segment!.count;
				if (seen.size === count) put("joined", id, [...Array(count).keys()].map((i) => seen.get(i)!.text!.trim()).join(" "));
			}
		} else {
			for (const r of mine) if (!texts.get(r.variant)?.has(r.clipId)) put(r.variant, r.clipId, r.text!);
		}
		const common = [...(texts.values().next().value?.keys() ?? [])].filter((id) => byId.has(id) && [...texts.values()].every((m) => m.has(id)));
		const set = common.map((id) => byId.get(id)!);
		console.log(`${name}: ${set.length} clips answered by every variant`);
		for (const [v, m] of texts) {
			const s = score(set, (c) => m.get(c.id), terms, ref);
			console.log(`  ${v}: WER ${((100 * s.errors) / Math.max(1, s.words)).toFixed(1)}% (${s.errors}/${s.words}), terms ${s.hits}/${s.terms}`);
		}
	}
}

if (exp === "score") {
	await scoreRows();
	process.exit(0);
}

if (exp === "report") {
	await report();
	process.exit(0);
}

const rounds = await plan();
const seconds = rounds.flat().reduce((s, j) => s + j.durationSec, 0);
const estimate = rounds.flat().reduce((s, j) => s + j.durationSec * (LISTED_USD_PER_SEC[j.variant.model] ?? 0.11 / 3600), 0);
console.log(`${exp}: ${rounds.flat().length} requests in ${rounds.length} rounds, ${Math.round(seconds)} s of audio, about $${estimate.toFixed(4)}`);
if (values["dry-run"]) process.exit(0);

const spent = await spentUsd([raw]);
const budget = new Budget(runCap === undefined ? COST_CAP_USD : spent + runCap, spent);
console.log(`spent so far: $${spent.toFixed(4)}; stops past $${budget.cap.toFixed(4)}`);
// One request first, so the connection is warm for every measured request, as the app warms at key-down.
await fetch(`${API}/models/${MAI}/endpoints`, { method: "HEAD" });
async function runRound(round: Job[], i: number): Promise<void> {
	const idle = Math.max(0, ...round.map((j) => j.idleBefore ?? 0));
	if (idle) await Bun.sleep(idle * 1000);
	const started: Promise<Row>[] = [];
	for (const job of round) {
		const before = job.after === "previous" ? started.slice(-1) : job.after === "all" ? [...started] : [];
		started.push(Promise.all(before).then(() => send(job)));
	}
	for (const r of await Promise.all(started)) {
		budget.add(r.cost);
		console.log(`  ${i + 1}/${rounds.length} ${r.variant} ${r.durationSec.toFixed(1)} s: ${r.status} ${Math.round(r.headersMs)} ms${r.error ? ` ${r.error.slice(0, 100)}` : ""}`);
	}
}
for (let i = 0; i < rounds.length && !budget.exceeded; i += parallel) {
	await Promise.all(rounds.slice(i, i + parallel).map((round, k) => runRound(round, i + k)));
}
console.log(`spent total: $${budget.total.toFixed(4)}`);
