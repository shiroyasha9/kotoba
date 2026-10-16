// L2 spike follow-up: which part of stream.ts does MAI refuse, the slow body or the open FLAC header? Sends one
// finished audio file in the app's JSON body, either at once or spread over --pace seconds (100 ms pieces), and
// appends one row to OUT/stream-raw.jsonl. Usage, from this folder:
//   bun --env-file=<env with OPENROUTER_API_KEY> probe.ts --out DIR --label NAME [--pace SEC] FILE
import { appendFileSync } from "node:fs";
import { extname, join } from "node:path";

const API = Bun.env.SPIKE_API ?? "https://openrouter.ai/api/v1"; // SPIKE_API: a local check server
const MODEL = "microsoft/mai-transcribe-2";

const args = Bun.argv.slice(2);
const flag = (name: string, fallback?: string) => {
	const i = args.indexOf(name);
	if (i < 0) {
		if (fallback === undefined) throw new Error(`missing ${name}`);
		return fallback;
	}
	return args.splice(i, 2)[1]!;
};
const outDir = flag("--out");
const label = flag("--label");
const pace = Number(flag("--pace", "0"));
const file = args[0]!;
const key = Bun.env.OPENROUTER_API_KEY;
if (!key) throw new Error("OPENROUTER_API_KEY is not set");

const audio = await Bun.file(file).bytes();
const format = extname(file).slice(1);
const encoder = new TextEncoder();
const head = encoder.encode(`{"input_audio":{"format":"${format}","data":"`);
const tail = encoder.encode(`"},${JSON.stringify({ language: "en", model: MODEL, provider: { zdr: true } }).slice(1)}`);

await fetch(`${API}/models/${MODEL}/endpoints`, { method: "HEAD", headers: { Authorization: `Bearer ${key}` } })
	.then((r) => r.arrayBuffer())
	.catch(() => {});
const marks: Record<string, number> = {};
const startedAt = new Date().toISOString();
const t0 = performance.now();
const pieces = pace > 0 ? Math.round(pace * 10) : 1;
const step = Math.ceil(audio.length / pieces / 3) * 3; // whole base64 groups per piece
const body = new ReadableStream<Uint8Array>({
	async start(c) {
		c.enqueue(head);
		for (let at = 0, i = 0; at < audio.length; at += step, i++) {
			if (pace > 0) await Bun.sleep(t0 + i * 100 - performance.now());
			c.enqueue(encoder.encode(audio.subarray(at, at + step).toBase64()));
		}
		c.enqueue(tail);
		marks.bodyDone = performance.now() - t0;
		c.close();
	},
});
let status = 0;
let parsed: unknown = null;
let error: string | undefined;
try {
	const res = await fetch(`${API}/audio/transcriptions`, {
		method: "POST",
		headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
		body,
		duplex: "half",
		signal: AbortSignal.timeout(120_000),
	} as RequestInit);
	marks.firstByte = performance.now() - t0;
	status = res.status;
	const text = await res.text();
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
	mode: `probe:${label}`,
	clip: file.split("/").pop(),
	startedAt,
	status,
	ok: status === 200 && typeof b?.text === "string",
	pace,
	fileBytes: audio.length,
	marks,
	bodyDoneToFirstByteMs: marks.firstByte !== undefined ? marks.firstByte - marks.bodyDone! : null,
	text: b?.text ?? null,
	usage: b?.usage ?? null,
	body: parsed,
	...(error ? { error } : {}),
};
appendFileSync(join(outDir, "stream-raw.jsonl"), JSON.stringify(row) + "\n");
console.log(
	`${label} status ${status} bodyDone->firstByte ${Math.round(row.bodyDoneToFirstByteMs ?? -1)} ms, seconds ${b?.usage?.seconds ?? "-"}, cost ${b?.usage?.cost ?? "-"}${error ? ` ERROR ${error.slice(0, 200)}` : ""}`,
);
