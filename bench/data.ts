// Input data (Wispr Flow export), references, dictionary and audio preparation.

import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";
import { appendJsonl, readJsonl, runPool } from "./openrouter.ts";

/** Seed for every sampled clip set (cleanup sample, latency sample), so reruns pick the same clips. */
export const BENCH_SEED = 20261015;

export type ManifestRow = {
	transcriptEntityId: string;
	timestamp: string | null;
	app: string | null;
	url: string | null;
	duration: number | null;
	numWords: number | null;
	e2eLatency: number | null;
	clientNetworkLatency: number | null;
	asrText: string | null;
	formattedText: string | null;
	editedText: string | null;
	pastedText: string | null;
};

export type DictionaryEntry = { phrase: string; replacement: string | null };

export type RefSource = "edited" | "wispr";

export type Clip = ManifestRow & {
	id: string;
	wavPath: string;
	reference: string;
	refSource: RefSource;
	refField: "editedText" | "pastedText" | "formattedText";
};

export type Paths = ReturnType<typeof paths>;

export function paths(dataDir: string) {
	const results = join(dataDir, "results");
	const sttRaw = join(results, "stt-raw.jsonl");
	const cleanupRaw = join(results, "cleanup-raw.jsonl");
	const latencyRaw = join(results, "latency-raw.jsonl");
	return {
		dataDir,
		clips: join(dataDir, "clips"),
		manifest: join(dataDir, "manifest.json"),
		dictionary: join(dataDir, "dictionary.json"),
		/** Hand-corrected references from `review/`, one row per save; the last row per clip wins. */
		references: join(dataDir, "references.jsonl"),
		/** The clip ids the review page asks about, fixed at its first start. */
		reviewSet: join(dataDir, "review-set.json"),
		results,
		audioDir: join(results, "audio"),
		audioIndex: join(results, "audio.jsonl"),
		sttRaw,
		cleanupRaw,
		latencyRaw,
		/** Every file with paid rows; the cost cap and the report sum `cost` over these. */
		rawFiles: [sttRaw, cleanupRaw, latencyRaw],
		runLog: join(results, "run-log.jsonl"),
		report: join(results, "report.md"),
	};
}

export const present = (s: string | null | undefined): s is string => typeof s === "string" && s.trim() !== "";

/** editedText when the user changed Wispr's output, else what Wispr pasted, else Wispr's formatted text. */
export function pickReference(row: ManifestRow): Pick<Clip, "reference" | "refSource" | "refField"> | null {
	if (present(row.editedText) && row.editedText.trim() !== (row.formattedText ?? "").trim()) {
		return { reference: row.editedText, refSource: "edited", refField: "editedText" };
	}
	if (present(row.pastedText)) return { reference: row.pastedText, refSource: "wispr", refField: "pastedText" };
	if (present(row.formattedText)) {
		return { reference: row.formattedText, refSource: "wispr", refField: "formattedText" };
	}
	return null;
}

export async function loadClips(p: Paths, limit?: number): Promise<{ clips: Clip[]; skipped: string[] }> {
	const rows: ManifestRow[] = await Bun.file(p.manifest).json();
	const clips: Clip[] = [];
	const skipped: string[] = [];
	for (const row of rows) {
		const id = row.transcriptEntityId;
		const wavPath = join(p.clips, `${id}.wav`);
		const ref = pickReference(row);
		if (!ref) {
			skipped.push(`${id}: no reference text`);
			continue;
		}
		if (!(await Bun.file(wavPath).exists())) {
			skipped.push(`${id}: missing ${wavPath}`);
			continue;
		}
		clips.push({ ...row, id, wavPath, ...ref });
	}
	clips.sort((a, b) => a.id.localeCompare(b.id));
	return { clips: limit ? clips.slice(0, limit) : clips, skipped };
}

export async function loadDictionary(p: Paths): Promise<DictionaryEntry[]> {
	return Bun.file(p.dictionary).json();
}

/** Every phrase and replacement, unique, in dictionary order. */
export function dictionaryTerms(dict: DictionaryEntry[]): string[] {
	const terms = dict.flatMap((e) => [e.phrase, e.replacement]).filter(present).map((t) => t.trim());
	return [...new Set(terms)];
}

/** The spelling the owner wants for each entry: its replacement, or the phrase itself for vocabulary-only entries. */
export function vocabulary(dict: DictionaryEntry[]): string[] {
	return [...new Set(dict.map((e) => (e.replacement ?? e.phrase).trim()).filter(Boolean))];
}

/** Case-insensitive whole-word phrase -> replacement, longest phrase first. */
export function applyDictionary(text: string, dict: DictionaryEntry[]): string {
	const entries = dict
		.filter((e): e is DictionaryEntry & { replacement: string } => present(e.phrase) && present(e.replacement))
		.sort((a, b) => b.phrase.length - a.phrase.length);
	let out = text;
	for (const e of entries) {
		const re = new RegExp(`(?<![\\p{L}\\p{N}_])${RegExp.escape(e.phrase.trim())}(?![\\p{L}\\p{N}_])`, "giu");
		out = out.replace(re, () => e.replacement);
	}
	return out;
}

export type AudioFormat = "flac" | "wav";

export type AudioInfo = { clipId: string; durationSec: number; wavBytes: number; flacBytes: number };

export function audioPath(p: Paths, clipId: string, format: AudioFormat): string {
	return join(p.audioDir, `${clipId}.16k.${format}`);
}

/**
 * Converts each clip to 16 kHz mono FLAC (what the app uploads) and records its
 * duration in audio.jsonl. Resume-safe: clips already indexed are skipped.
 */
export async function prepareAudio(p: Paths, clips: Clip[]): Promise<Map<string, AudioInfo>> {
	await mkdir(p.audioDir, { recursive: true });
	const index = new Map((await readJsonl<AudioInfo>(p.audioIndex)).map((r) => [r.clipId, r]));
	await runPool(
		clips,
		navigator.hardwareConcurrency,
		async (clip) => {
			const flac = audioPath(p, clip.id, "flac");
			if (index.has(clip.id) && (await Bun.file(flac).exists())) return;
			await $`ffmpeg -hide_banner -loglevel error -y -i ${clip.wavPath} -ac 1 -ar 16000 -c:a flac ${flac}`;
			const durationSec = Number(
				(await $`ffprobe -v error -show_entries format=duration -of csv=p=0 ${flac}`.text()).trim(),
			);
			const info: AudioInfo = {
				clipId: clip.id,
				durationSec,
				wavBytes: Bun.file(clip.wavPath).size,
				flacBytes: Bun.file(flac).size,
			};
			await appendJsonl(p.audioIndex, info);
			index.set(clip.id, info);
		},
		() => false,
	);
	return index;
}

const wav16Jobs = new Map<string, Promise<string>>();

/** 16 kHz mono WAV, made only when a provider rejects FLAC; one conversion per clip even under concurrency. */
export function ensureWav16(p: Paths, clip: Clip): Promise<string> {
	let job = wav16Jobs.get(clip.id);
	if (!job) {
		const wav = audioPath(p, clip.id, "wav");
		job = (async () => {
			if (!(await Bun.file(wav).exists())) {
				await $`ffmpeg -hide_banner -loglevel error -y -i ${clip.wavPath} -ac 1 -ar 16000 -c:a pcm_s16le ${wav}`;
			}
			return wav;
		})();
		wav16Jobs.set(clip.id, job);
	}
	return job;
}

export const DURATION_BUCKETS = ["<10 s", "10-20 s", "20-40 s", ">40 s"] as const;
export type DurationBucket = (typeof DURATION_BUCKETS)[number];

export function durationBucket(sec: number): DurationBucket {
	if (sec < 10) return "<10 s";
	if (sec < 20) return "10-20 s";
	if (sec <= 40) return "20-40 s";
	return ">40 s";
}

/** mulberry32: small seeded PRNG in [0, 1). */
export function mulberry32(seed: number): () => number {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6d2b79f5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

/** Fisher-Yates shuffle of a copy, driven by `rand`. */
export function shuffle<T>(items: T[], rand: () => number): T[] {
	const out = [...items];
	for (let i = out.length - 1; i > 0; i--) {
		const j = Math.floor(rand() * (i + 1));
		[out[i], out[j]] = [out[j]!, out[i]!];
	}
	return out;
}

/** Deterministic sample of `n` items (mulberry32-seeded shuffle). */
export function seededSample<T>(items: T[], n: number, seed = BENCH_SEED): T[] {
	return shuffle(items, mulberry32(seed)).slice(0, n);
}
