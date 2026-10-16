// Synthetic Writing bench entry point: kotoba's Writing cleanup prompt on TTS-spoken messages, mail and notes.
// bun run writing [--only tts|stt|cleanup|report] [--concurrency N] [--cap USD] [--dry-run] [--data DIR] [--real DIR]
// A run without --only does TTS, STT (one variant), the Writing cleanup, then the report and the pairs file.

import { parseArgs } from "node:util";
import { fail, intArg } from "../cli.ts";
import { CLEANUP_MODELS, PINNED_PROVIDERS, runCleanup } from "../cleanup.ts";
import { loadDictionary, prepareAudio, vocabulary } from "../data.ts";
import { Budget, confirmModels, spentUsd } from "../openrouter.ts";
import { LISTED_USD_PER_SEC, MAI, type SttVariantKey, runVariants, sttVariants } from "../stt.ts";
import { TTS_CONCURRENCY, VOICES, confirmTtsModel, plannedSec, runTts, spokenClip, synthesized, ttsPaths } from "../tts.ts";
import { type WritingClip, writeWritingReport } from "./report.ts";
import { TEXTS } from "./texts.ts";

/** Default cap on all spend recorded in this bench's raw files, across runs. `--cap` sets a per-run cap instead. */
const COST_CAP_USD = 0.25;
const PASSES = ["tts", "stt", "cleanup", "report"] as const;
type Pass = (typeof PASSES)[number];

/** The cleanup input in kotoba-bench-v1 (lowest WER there). It is the only STT variant this bench runs, so `runCleanup` picks it. */
const INPUT_VARIANT: SttVariantKey = "mai+phraseList";
/** Dry-run estimate: mean cost per call by cleanup model in kotoba-bench-v1's cleanup-raw.jsonl (2026-10-16). */
const PLANNED_CLEANUP_USD: Record<string, number> = {
	"qwen3.8-27b@cerebras": 0.00066,
	"gemini-3.5-flash-lite": 0.00037,
	"claude-haiku-5.5": 0.00013,
};

const { values } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		only: { type: "string" },
		concurrency: { type: "string", default: "16" },
		cap: { type: "string" },
		"dry-run": { type: "boolean", default: false },
		// This bench's folder: dictionary.json (a copy of kotoba-bench-v1's, so the prompt carries the same vocabulary), clips/, results/.
		data: { type: "string", default: Bun.env.KOTOBA_WRITING_DATA },
		// kotoba-bench-v1's folder, read only: its Writing-app clips go into the pairs file next to the synthetic ones.
		real: { type: "string", default: Bun.env.KOTOBA_BENCH_DATA },
	},
});

const only = values.only as Pass | undefined;
if (only && !PASSES.includes(only)) fail(`--only must be one of ${PASSES.join(", ")}`);
const concurrency = intArg(values, "concurrency", 1)!;
const runCap = values.cap === undefined ? undefined : Number(values.cap);
if (runCap !== undefined && !(runCap > 0)) fail("--cap must be a positive number of USD");
const dryRun = values["dry-run"];
if (!values.data) fail("set KOTOBA_WRITING_DATA or pass --data DIR");
const runs = (pass: Pass) => !only || only === pass;

const p = ttsPaths(values.data);
const dict = await loadDictionary(p);
// One clip per text, from its Writing app, voices in turn; the reference is the text the speaker meant.
const clips: WritingClip[] = TEXTS.map((text, i) =>
	spokenClip(p, { id: text.id, app: text.app, reference: text.reference, text, voice: VOICES[i % VOICES.length]! }),
);
console.log(`data: ${p.dataDir}`);
console.log(`clips: ${clips.length}, ${clips.filter((c) => c.text.trap).length} traps; dictionary: ${dict.length} entries`);

if (only !== "report") {
	if (!dryRun) {
		await Promise.all([confirmTtsModel(), confirmModels([MAI], CLEANUP_MODELS.map((m) => m.model), PINNED_PROVIDERS)]);
		console.log("models confirmed on OpenRouter");
	}
	const spent = await spentUsd(p.rawFiles);
	const budget = new Budget(runCap === undefined ? COST_CAP_USD : spent + runCap, spent);
	console.log(`spent so far (from raw files): $${spent.toFixed(4)}; this run stops past $${budget.cap.toFixed(4)} total`);
	if (runs("tts")) await runTts(p, clips, budget, Math.min(concurrency, TTS_CONCURRENCY), dryRun);

	const done = await synthesized(p, clips);
	const voiced = clips.filter((c) => done.has(c.id));
	if (dryRun) {
		// Before TTS there is no audio to measure: plan from the text length.
		const sec = clips.reduce((s, c) => s + plannedSec(c), 0);
		const sttUsd = sec * LISTED_USD_PER_SEC[MAI]!;
		const cleanupUsd = clips.length * CLEANUP_MODELS.reduce((s, m) => s + (PLANNED_CLEANUP_USD[m.key] ?? 0), 0);
		console.log(`\nSTT plan: ${INPUT_VARIANT}, ${clips.length} calls, ~${(sec / 60).toFixed(1)} min audio, ~$${sttUsd.toFixed(3)}`);
		console.log(
			`Cleanup plan (Writing prompt): ${clips.length} clips x ${CLEANUP_MODELS.length} models = ` +
				`${clips.length * CLEANUP_MODELS.length} calls, ~$${cleanupUsd.toFixed(3)} at kotoba-bench-v1's mean cost per call`,
		);
	} else if (voiced.length && !budget.exceeded) {
		const audio = await prepareAudio(p, voiced);
		const ctx = { p, clips: voiced, audio, dict, budget, concurrency, dryRun: false, passthroughProbe: 0 };
		const variant = sttVariants(dict).find((v) => v.key === INPUT_VARIANT)!;
		if (runs("stt")) await runVariants(ctx, INPUT_VARIANT, [[variant, voiced]]);
		if (runs("cleanup") && !budget.exceeded) {
			await runCleanup({ p, clips: voiced, vocabulary: vocabulary(dict), budget, concurrency, dryRun: false, prompt: "writing" });
		}
	}
	console.log(`spent total: $${budget.total.toFixed(4)}`);
}

if (dryRun && only !== "report") {
	console.log("\ndry run: no requests sent, report not written");
} else {
	const { report, pairs } = await writeWritingReport(p, clips, dict, values.real);
	console.log(`\nreport: ${report}\npairs: ${pairs}`);
}
