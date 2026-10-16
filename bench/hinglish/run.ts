// Synthetic Hinglish bench entry point.
// bun run hinglish [--only tts|stt|latency|report] [--limit N] [--concurrency N] [--cap USD] [--dry-run] [--data DIR]
// A run without --only does TTS, the STT accuracy pass, the sequential latency pass, then the report.

import { parseArgs } from "node:util";
import { fail, intArg } from "../cli.ts";
import { type AudioInfo, prepareAudio, seededSample } from "../data.ts";
import { Budget, confirmModels, okRowsByVariant, readJsonl, runCalls, spentUsd } from "../openrouter.ts";
import { GROK, LISTED_USD_PER_SEC, MAI, type SttRow, runVariants, transcribe } from "../stt.ts";
import { TTS_CONCURRENCY, confirmTtsModel, plannedSec, runTts, synthesized, ttsPaths } from "../tts.ts";
import { writeHinglishReport } from "./report.ts";
import { type HinglishClip, hinglishClips } from "./texts.ts";
import { LATENCY_CLIPS, VARIANTS } from "./variants.ts";

/** Default cap on all spend recorded in this bench's raw files, across runs. `--cap` sets a per-run cap instead. */
const COST_CAP_USD = 1.5;
const PASSES = ["tts", "stt", "latency", "report"] as const;
type Pass = (typeof PASSES)[number];


const { values } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		only: { type: "string" },
		limit: { type: "string" },
		concurrency: { type: "string", default: "16" },
		cap: { type: "string" },
		"dry-run": { type: "boolean", default: false },
		data: { type: "string", default: Bun.env.KOTOBA_HINGLISH_DATA },
	},
});

const only = values.only as Pass | undefined;
if (only && !PASSES.includes(only)) fail(`--only must be one of ${PASSES.join(", ")}`);
const limit = intArg(values, "limit", 1);
const concurrency = intArg(values, "concurrency", 1)!;
const runCap = values.cap === undefined ? undefined : Number(values.cap);
if (runCap !== undefined && !(runCap > 0)) fail("--cap must be a positive number of USD");
const dryRun = values["dry-run"];
if (!values.data) fail("set KOTOBA_HINGLISH_DATA or pass --data DIR");
const runs = (pass: Pass) => !only || only === pass;

const p = ttsPaths(values.data);
const all = hinglishClips(p);
const clips = limit ? all.slice(0, limit) : all;
console.log(`data: ${p.dataDir}`);
console.log(`clips: ${clips.length} of ${all.length} (${new Set(clips.map((c) => c.text.id)).size} texts)`);

/** Sequential pass on seeded Hinglish clips, the variant order reversed on every other clip; rows go to latency-raw.jsonl. */
async function runLatency(voiced: HinglishClip[], audio: Map<string, AudioInfo>, budget: Budget): Promise<void> {
	const sample = seededSample(
		voiced.filter((c) => c.text.set === "hinglish"),
		LATENCY_CLIPS,
	);
	const done = okRowsByVariant(await readJsonl<SttRow>(p.latencyRaw));
	const queue = sample.flatMap((c, i) =>
		(i % 2 ? [...VARIANTS].reverse() : VARIANTS).filter((v) => !done.get(v.key)?.has(c.id)).map((v) => ({ v, c })),
	);
	console.log(`\nLatency pass: ${sample.length} Hinglish clips, ${queue.length} sequential calls pending`);
	if (dryRun || !queue.length || budget.exceeded) return;
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
}

if (only !== "report") {
	if (!dryRun) {
		await Promise.all([confirmTtsModel(), confirmModels([GROK, MAI], [], [])]);
		console.log("models confirmed on OpenRouter");
	}
	const spent = await spentUsd(p.rawFiles);
	const budget = new Budget(runCap === undefined ? COST_CAP_USD : spent + runCap, spent);
	console.log(`spent so far (from raw files): $${spent.toFixed(4)}; this run stops past $${budget.cap.toFixed(4)} total`);
	if (runs("tts")) await runTts(p, clips, budget, Math.min(concurrency, TTS_CONCURRENCY), dryRun);

	const done = await synthesized(p, clips);
	const voiced = clips.filter((c) => done.has(c.id));
	if (dryRun && (runs("stt") || runs("latency"))) {
		// Before TTS there is no audio to measure: plan from the text length.
		const sec = clips.reduce((s, c) => s + plannedSec(c), 0);
		const calls = clips.length * VARIANTS.length + LATENCY_CLIPS * VARIANTS.length;
		const audioSec = sec * VARIANTS.length * (1 + LATENCY_CLIPS / clips.length);
		console.log(
			`\nSTT plan: ${VARIANTS.map((v) => v.key).join(", ")}; ${calls} calls, ~${(audioSec / 60).toFixed(0)} min audio, ` +
				`~$${(audioSec * LISTED_USD_PER_SEC[MAI]!).toFixed(3)} at listed price (accuracy pass + ${LATENCY_CLIPS}-clip latency pass)`,
		);
	} else if (!budget.exceeded && voiced.length && (runs("stt") || runs("latency"))) {
		const audio = await prepareAudio(p, voiced);
		const ctx = { p, clips: voiced, audio, dict: [], budget, concurrency, dryRun, passthroughProbe: 0 };
		if (runs("stt")) await runVariants(ctx, "Hinglish variants", VARIANTS.map((v) => [v, voiced]));
		if (runs("latency") && !budget.exceeded) await runLatency(voiced, audio, budget);
	}
	console.log(`spent total: $${budget.total.toFixed(4)}`);
}

if (dryRun && only !== "report") {
	console.log("\ndry run: no requests sent, report not written");
} else {
	console.log(`\nreport: ${await writeHinglishReport(p, all)}`);
}
