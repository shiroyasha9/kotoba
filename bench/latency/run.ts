// Latency probe: where does the time between the last body byte and the answer go, and which request shape is fastest?
// bun run latency --exp duration|shape|hedge|models|idle|primer|spacing [--clips N] [--repeat N] [--models SLUG,SLUG] [--cap USD] [--dry-run]
//   [--data DIR] [--out DIR]
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
import { type AudioInfo, audioPath, loadDictionary, paths, seededSample } from "../data.ts";
import { API, Budget, appendJsonl, authHeaders, readJsonl, spentUsd } from "../openrouter.ts";
import { fmtMs, percentile } from "../report.ts";
import { LISTED_USD_PER_SEC, MAI, biasTerms } from "../stt.ts";

/** Default cap on this probe's raw file, across runs. */
const COST_CAP_USD = 0.5;
const EXPERIMENTS = ["duration", "shape", "hedge", "models", "idle", "primer", "spacing", "report"] as const;
type Experiment = (typeof EXPERIMENTS)[number];
/** Trim lengths for the duration sweep, in seconds. */
const DURATIONS = [3, 6, 10, 15, 20, 30];
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
	error?: string;
};

const terms = biasTerms(await loadDictionary(p));

function variant(key: string, model: string, over: Partial<Variant> = {}): Variant {
	return { key, model, body: "json", zdr: model === MAI, phrases: model === MAI, ...over };
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
		input_audio: { format: file.endsWith(".wav") ? "wav" : "flac", data: audio.toBase64() },
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
	for (const r of rows) if (r.exp === "hedge" && r.ok && r.pair) pairs.set(`${r.pair} ${r.startedAt.slice(0, 16)}`, [...(pairs.get(`${r.pair} ${r.startedAt.slice(0, 16)}`) ?? []), r.headersMs]);
	const best = [...pairs.values()].filter((v) => v.length === 2).map((v) => Math.min(...v));
	if (best.length) console.log(`hedge faster-of-two: ${best.length} pairs, p50 ${fmtMs(percentile(best, 0.5))} ms, p90 ${fmtMs(percentile(best, 0.9))} ms`);
	console.log(`spent in ${raw}: $${(await spentUsd([raw])).toFixed(4)}`);
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
for (const [i, round] of rounds.entries()) {
	if (budget.exceeded) break;
	const idle = Math.max(0, ...round.map((j) => j.idleBefore ?? 0));
	if (idle) await Bun.sleep(idle * 1000);
	const rows = await Promise.all(round.map(send));
	for (const r of rows) {
		budget.add(r.cost);
		console.log(`  ${i + 1}/${rounds.length} ${r.variant} ${r.durationSec.toFixed(1)} s: ${r.status} ${Math.round(r.headersMs)} ms${r.error ? ` ${r.error.slice(0, 100)}` : ""}`);
	}
}
console.log(`spent total: $${budget.total.toFixed(4)}`);
