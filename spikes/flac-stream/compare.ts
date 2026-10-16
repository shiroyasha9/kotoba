// L2 spike, timing pass: does sending the audio while recording shorten stop -> first byte on OpenRouter MAI? Each
// clip goes three ways, all in the app's JSON body (OpenRouterProvider.swift), all after the app's warm-up HEAD and a
// simulated recording as long as the clip:
//   wav-stream  a WAV with RIFF and data sizes 0xFFFFFFFF (unknown, the streaming convention) sent from the first
//               100 ms of the recording at real-time pace; at the stop only the last piece and the closing fields remain.
//   wav-once    the finished WAV (real sizes), sent at once after the stop.
//   flac-once   the app today: the finished FLAC (written by build/writer), sent at once after the stop.
// The mode order turns by one on every clip. Every request appends one JSON row to OUT/compare-raw.jsonl as it
// completes; the run stops before a request when that file's cost reaches --cap. Usage, from this folder:
//   bun --env-file=<env with OPENROUTER_API_KEY> compare.ts --clips DIR --flac DIR --out DIR --cap USD CLIP...
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { wer } from "../../bench/score.ts";

const API = Bun.env.SPIKE_API ?? "https://openrouter.ai/api/v1"; // SPIKE_API: a local check server
const MODEL = "microsoft/mai-transcribe-2";
const MODES = ["wav-stream", "wav-once", "flac-once"] as const;
type Mode = (typeof MODES)[number];
const WAV_HEADER = 44;
const PIECE = 3_200; // 100 ms of 16 kHz mono Int16

const args = Bun.argv.slice(2);
const flag = (name: string) => {
	const i = args.indexOf(name);
	if (i < 0 || !args[i + 1]) throw new Error(`missing ${name}`);
	return args.splice(i, 2)[1]!;
};
const clipsDir = flag("--clips");
const flacDir = flag("--flac");
const outDir = flag("--out");
const cap = Number(flag("--cap"));
if (!(cap > 0)) throw new Error("--cap needs a positive USD amount");
const clips = args;
const key = Bun.env.OPENROUTER_API_KEY;
if (!key) throw new Error("OPENROUTER_API_KEY is not set");
const rawFile = join(outDir, "compare-raw.jsonl");

function rows(): Array<Record<string, any>> {
	if (!existsSync(rawFile)) return [];
	return readFileSync(rawFile, "utf8")
		.split("\n")
		.filter(Boolean)
		.map((line) => JSON.parse(line));
}
const spent = () => rows().reduce((sum, r) => sum + (r.usage?.cost ?? 0), 0);

const encoder = new TextEncoder();
const tail = encoder.encode(`"},${JSON.stringify({ language: "en", model: MODEL, provider: { zdr: true } }).slice(1)}`);
const head = (format: string) => encoder.encode(`{"input_audio":{"format":"${format}","data":"`);

async function run(mode: Mode, clip: string) {
	const wav = await Bun.file(join(clipsDir, `${clip}.wav`)).bytes();
	// The clips are ffmpeg WAVs written with -map_metadata -1 -fflags +bitexact: a 44-byte header, no LIST chunk.
	if (new TextDecoder().decode(wav.subarray(36, 40)) !== "data") throw new Error(`${clip}.wav: data chunk not at 36`);
	const pcm = wav.subarray(WAV_HEADER);
	const flac = mode === "flac-once" ? await Bun.file(join(flacDir, `${clip}.flac`)).bytes() : null;
	const audioSec = pcm.length / 32_000;
	await fetch(`${API}/models/${MODEL}/endpoints`, { method: "HEAD", headers: { Authorization: `Bearer ${key}` } })
		.then((r) => r.arrayBuffer())
		.catch(() => {});
	const marks: Record<string, number> = {};
	const startedAt = new Date().toISOString();
	const t0 = performance.now();
	const tick = (i: number) => Bun.sleep(t0 + i * 100 - performance.now());
	const pieces = Math.ceil(pcm.length / PIECE);
	let controller!: ReadableStreamDefaultController<Uint8Array>;
	const body = new ReadableStream<Uint8Array>({ start: (c) => void (controller = c) });
	let bodyBytes = 0;
	const enqueue = (bytes: Uint8Array) => {
		bodyBytes += bytes.length;
		controller.enqueue(bytes);
	};
	const post = () =>
		fetch(`${API}/audio/transcriptions`, {
			method: "POST",
			headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
			body,
			duplex: "half",
			signal: AbortSignal.timeout(120_000),
		} as RequestInit);
	let response: Promise<Response>;
	if (mode === "wav-stream") {
		const header = wav.slice(0, WAV_HEADER);
		new DataView(header.buffer).setUint32(4, 0xffff_ffff, true);
		new DataView(header.buffer).setUint32(40, 0xffff_ffff, true);
		enqueue(head("wav"));
		// 44 header bytes + 3,200-byte pieces: 44 = 14 x 3 + 2, so carry the 2 bytes into each next piece's base64.
		let carry = header;
		response = post();
		marks.requestOpen = performance.now() - t0;
		for (let i = 0; i < pieces; i++) {
			await tick(i + 1); // a piece is sent when its 100 ms have been recorded
			const piece = pcm.subarray(i * PIECE, (i + 1) * PIECE);
			const all = new Uint8Array(carry.length + piece.length);
			all.set(carry);
			all.set(piece, carry.length);
			const last = i === pieces - 1;
			const cut = last ? all.length : all.length - (all.length % 3);
			if (last) {
				marks.stop = performance.now() - t0;
				marks.bytesBeforeStop = bodyBytes;
			}
			enqueue(encoder.encode(all.subarray(0, cut).toBase64()));
			carry = all.slice(cut);
		}
	} else {
		await tick(pieces);
		marks.stop = performance.now() - t0;
		marks.bytesBeforeStop = 0;
		enqueue(head(flac ? "flac" : "wav"));
		response = post();
		marks.requestOpen = performance.now() - t0;
		enqueue(encoder.encode((flac ?? wav).toBase64()));
	}
	enqueue(tail);
	controller.close();
	marks.bodyDone = performance.now() - t0;

	let status = 0;
	let parsed: unknown = null;
	let error: string | undefined;
	try {
		const res = await response;
		marks.firstByte = performance.now() - t0;
		status = res.status;
		const text = await res.text();
		marks.done = performance.now() - t0;
		try {
			parsed = JSON.parse(text);
		} catch {
			parsed = { raw: text.slice(0, 2000) };
		}
		if (!res.ok) error = text.slice(0, 500);
	} catch (e) {
		error = String(e);
	}
	const b = parsed as { text?: string; usage?: { cost?: number; seconds?: number } } | null;
	const row = {
		mode,
		clip,
		startedAt,
		status,
		ok: status === 200 && typeof b?.text === "string",
		audioSec,
		bodyBytes,
		marks,
		stopToFirstByteMs: marks.firstByte !== undefined ? marks.firstByte - marks.stop! : null,
		text: b?.text ?? null,
		usage: b?.usage ?? null,
		body: parsed,
		...(error ? { error } : {}),
	};
	appendFileSync(rawFile, JSON.stringify(row) + "\n");
	console.log(
		`${clip.padEnd(4)} ${mode.padEnd(10)} status ${status} stop->firstByte ${Math.round(row.stopToFirstByteMs ?? -1)} ms, ` +
			`body ${bodyBytes} B, cost ${b?.usage?.cost ?? "-"}${error ? ` ERROR ${error.slice(0, 200)}` : ""}`,
	);
}

const runStart = new Date().toISOString();
done: for (const [n, clip] of clips.entries()) {
	for (const k of MODES.keys()) {
		const total = spent();
		if (total >= cap) {
			console.log(`cap $${cap} reached ($${total.toFixed(5)} spent): stop`);
			break done;
		}
		await run(MODES[(k + n) % MODES.length]!, clip);
	}
}

// This run's rows only: the file keeps earlier runs. Word errors use the bench's normalization (bench/score.ts).
const all = rows().filter((r) => clips.includes(r.clip) && r.startedAt >= runStart);
const percentile = (xs: number[], p: number) => [...xs].sort((a, b) => a - b)[Math.max(0, Math.ceil(p * xs.length) - 1)];
for (const mode of MODES) {
	const ok = all.filter((r) => r.mode === mode && r.ok).map((r) => r.stopToFirstByteMs as number);
	const failed = all.filter((r) => r.mode === mode && !r.ok).length;
	console.log(
		`${mode.padEnd(10)} ok ${ok.length} failed ${failed} stop->firstByte p50 ${Math.round(percentile(ok, 0.5) ?? -1)} ms, ` +
			`min ${Math.round(Math.min(...ok))}, max ${Math.round(Math.max(...ok))}`,
	);
}
for (const clip of clips) {
	const base = all.find((r) => r.clip === clip && r.mode === "flac-once" && r.ok);
	const others = MODES.filter((m) => m !== "flac-once").map((m) => {
		const r = all.find((x) => x.clip === clip && x.mode === m && x.ok);
		return `${m} ${r && base ? `${wer(base.text, r.text).errors} word errors` : "-"}`;
	});
	console.log(`${clip.padEnd(4)} vs flac-once (${base ? wer(base.text, base.text).refWords : "-"} words): ${others.join(", ")}`);
}
console.log(`spent $${spent().toFixed(5)} over ${rawFile}`);
