// L2 spike (docs/research/quality-perf-2.md): send a dictation to OpenRouter MAI while it is still being recorded.
// The Swift writer (main.swift) writes a WAV to FLAC at real-time pace and prints one line per write; this script
// sends the new FLAC bytes as they land, inside the app's JSON body (KotobaProviders OpenRouterProvider.swift):
// `{"input_audio":{"format":"flac","data":"<base64>"},"language":"en","model":...,"provider":{"zdr":true}}`.
//
// Modes:
//   normal     the app today: wait for close, then send the finished file.
//   stream     body open from the first write; a made-up STREAMINFO (total samples 0, frame sizes 0, MD5 0, all
//              "unknown" in the FLAC format), then bytes 42.. as written.
//   zeroed     like stream, but the header as AVAudioFile has it on disk before close (STREAMINFO all zeros).
//   multipart  stream, as OpenAI-style multipart/form-data with the raw FLAC (no base64, no provider options).
//
// Every request appends one JSON row to OUT/stream-raw.jsonl as it completes. Usage, from this folder:
//   bun --env-file=<env with OPENROUTER_API_KEY> stream.ts --clips DIR --out DIR --cap USD MODE:CLIP [MODE:CLIP ...]
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const API = Bun.env.SPIKE_API ?? "https://openrouter.ai/api/v1"; // SPIKE_API: a local check server
const MODEL = "microsoft/mai-transcribe-2";
const WRITER = join(import.meta.dir, "build/writer");
const HEADER_BYTES = 42; // "fLaC" + STREAMINFO block header (4) + STREAMINFO (34)

type Mode = "normal" | "stream" | "zeroed" | "multipart";

const args = Bun.argv.slice(2);
const flag = (name: string) => {
	const i = args.indexOf(name);
	if (i < 0 || !args[i + 1]) throw new Error(`missing ${name}`);
	return args.splice(i, 2)[1]!;
};
const clipsDir = flag("--clips");
const outDir = flag("--out");
const cap = Number(flag("--cap"));
if (!(cap > 0)) throw new Error("--cap needs a positive USD amount");
const jobs = args.map((a) => {
	const [mode, clip] = a.split(":") as [Mode, string];
	return { mode, clip };
});
const key = Bun.env.OPENROUTER_API_KEY;
if (!key) throw new Error("OPENROUTER_API_KEY is not set");
mkdirSync(join(outDir, "flac"), { recursive: true });
const rawFile = join(outDir, "stream-raw.jsonl");

function spent(): number {
	if (!existsSync(rawFile)) return 0;
	return readFileSync(rawFile, "utf8")
		.split("\n")
		.filter(Boolean)
		.reduce((sum, line) => sum + ((JSON.parse(line).usage?.cost as number | undefined) ?? 0), 0);
}

/** STREAMINFO with what the writer's settings fix (Apple's encoder uses 4,608-sample blocks) and the rest unknown. */
function streamHeader(): Uint8Array {
	const header = new Uint8Array(HEADER_BYTES);
	header.set(new TextEncoder().encode("fLaC"), 0);
	header.set([0x00, 0, 0, 34], 4);
	const view = new DataView(header.buffer);
	view.setUint16(8, 4608);
	view.setUint16(10, 4608);
	// Bytes 12-17 frame sizes 0. Then 20 bits rate, 3 bits channels-1, 5 bits bits-1, 36 bits total samples (0).
	const packed = (16000n << 44n) | (0n << 41n) | (15n << 36n);
	view.setBigUint64(18, packed);
	return header; // MD5 (26-41) stays 0.
}

/** Base64 of a byte stream fed in pieces: holds back the 0-2 bytes that do not fill a 3-byte group. */
class Base64Chunker {
	private carry = new Uint8Array(0);
	push(bytes: Uint8Array, final = false): string {
		const all = new Uint8Array(this.carry.length + bytes.length);
		all.set(this.carry);
		all.set(bytes, this.carry.length);
		const cut = final ? all.length : all.length - (all.length % 3);
		this.carry = all.slice(cut);
		return all.subarray(0, cut).toBase64();
	}
}

const now = () => performance.now();

async function warm() {
	// The app's warm-up: opens TCP and TLS on the connection the upload reuses.
	await fetch(`${API}/models/${MODEL}/endpoints`, { method: "HEAD", headers: { Authorization: `Bearer ${key}` } })
		.then((r) => r.arrayBuffer())
		.catch(() => {});
}

async function run(mode: Mode, clip: string) {
	const flac = join(outDir, "flac", `${clip}-${mode}.flac`);
	const encoder = new TextEncoder();
	const tail = JSON.stringify({ language: "en", model: MODEL, provider: { zdr: true } }).slice(1); // drop "{"
	const boundary = "kotoba-spike-boundary";
	let controller!: ReadableStreamDefaultController<Uint8Array>;
	const body = new ReadableStream<Uint8Array>({ start: (c) => void (controller = c) });
	const chunker = new Base64Chunker();
	let sent = 0; // file bytes already in the body
	let bodyBytes = 0;
	const enqueue = (bytes: Uint8Array) => {
		bodyBytes += bytes.length;
		controller.enqueue(bytes);
	};
	const sendAudio = (bytes: Uint8Array, final = false) =>
		mode === "multipart" ? enqueue(bytes) : enqueue(encoder.encode(chunker.push(bytes, final)));
	const sendNewBytes = async (final: boolean) => {
		const size = Bun.file(flac).size;
		if (sent === 0) {
			if (size < HEADER_BYTES) return;
			const disk = new Uint8Array(await Bun.file(flac).slice(0, HEADER_BYTES).arrayBuffer());
			sendAudio(mode === "zeroed" ? disk : streamHeader());
			sent = HEADER_BYTES;
		}
		if (size > sent) {
			sendAudio(new Uint8Array(await Bun.file(flac).slice(sent, size).arrayBuffer()), final);
			sent = size;
		} else if (final) sendAudio(new Uint8Array(0), true);
	};

	await warm();
	const marks: Record<string, number> = {};
	const startedAt = new Date().toISOString();
	const t0 = now();
	let response: Promise<Response> | null = null;
	const open = () => {
		const multipart = mode === "multipart";
		if (multipart) {
			const fields = [
				["model", MODEL],
				["language", "en"],
			]
				.map(([k, v]) => `--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`)
				.join("");
			enqueue(
				encoder.encode(
					`${fields}--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="audio.flac"\r\nContent-Type: audio/flac\r\n\r\n`,
				),
			);
		} else enqueue(encoder.encode(`{"input_audio":{"format":"flac","data":"`));
		marks.requestOpen = now() - t0;
		return fetch(`${API}/audio/transcriptions`, {
			method: "POST",
			headers: {
				Authorization: `Bearer ${key}`,
				"Content-Type": multipart ? `multipart/form-data; boundary=${boundary}` : "application/json",
			},
			body,
			duplex: "half",
			signal: AbortSignal.timeout(120_000),
		} as RequestInit).then((res) => {
			// The headers can arrive while the writer still runs; mark them then, not after it exits.
			marks.firstByte = now() - t0;
			return res;
		});
	};
	const finish = () => {
		enqueue(encoder.encode(mode === "multipart" ? `\r\n--${boundary}--\r\n` : `"},${tail}`));
		controller.close();
	};

	const writer = Bun.spawn([WRITER, join(clipsDir, `${clip}.wav`), flac, "--realtime"], { stdout: "pipe" });
	const lines = writer.stdout.pipeThrough(new TextDecoderStream());
	let buffer = "";
	let writes = 0;
	for await (const text of lines) {
		buffer += text;
		let nl: number;
		while ((nl = buffer.indexOf("\n")) >= 0) {
			const event = JSON.parse(buffer.slice(0, nl)) as { event: string; size: number };
			buffer = buffer.slice(nl + 1);
			if (event.event === "write") {
				writes++;
				if (mode !== "normal") {
					response ??= open();
					await sendNewBytes(false);
				}
			} else if (event.event === "stop") {
				marks.stop = now() - t0;
				marks.sentAtStop = sent;
			} else if (event.event === "closed") {
				marks.closed = now() - t0;
				if (mode === "normal") {
					const audio = await Bun.file(flac).bytes();
					response = open();
					sent = audio.length;
					sendAudio(audio, true);
				} else await sendNewBytes(true);
				finish();
				marks.bodyDone = now() - t0;
			}
		}
	}
	await writer.exited;

	let status = 0;
	let parsed: unknown = null;
	let error: string | undefined;
	let generationId: string | null = null;
	try {
		const res = await response!;
		status = res.status;
		generationId = res.headers.get("x-generation-id");
		const text = await res.text();
		marks.done = now() - t0;
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
		writes,
		fileBytes: Bun.file(flac).size,
		sentBytes: sent,
		bodyBytes,
		marks,
		stopToFirstByteMs: marks.firstByte !== undefined ? marks.firstByte - marks.stop! : null,
		stopToDoneMs: marks.done !== undefined ? marks.done - marks.stop! : null,
		generationId,
		text: b?.text ?? null,
		usage: b?.usage ?? null,
		body: parsed,
		...(error ? { error } : {}),
	};
	appendFileSync(rawFile, JSON.stringify(row) + "\n");
	console.log(
		`${mode.padEnd(9)} ${clip} status ${status} stop->firstByte ${Math.round(row.stopToFirstByteMs ?? -1)} ms, ` +
			`body at stop ${marks.sentAtStop}/${row.fileBytes} B, seconds ${b?.usage?.seconds ?? "-"}, cost ${b?.usage?.cost ?? "-"}${error ? ` ERROR ${error.slice(0, 200)}` : ""}`,
	);
}

for (const { mode, clip } of jobs) {
	const total = spent();
	if (total >= cap) {
		console.log(`cap $${cap} reached ($${total.toFixed(5)} spent): stop`);
		break;
	}
	await run(mode, clip);
}
console.log(`spent $${spent().toFixed(5)} over ${rawFile}`);
