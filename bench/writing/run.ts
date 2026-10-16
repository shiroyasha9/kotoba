// Synthetic Writing bench entry point: kotoba's Writing cleanup prompt on TTS-spoken messages, mail and notes.
// bun run writing [--only tts|stt|cleanup|report] [--traps] [--models KEY,KEY] [--levers KEY,KEY] [--clips ID,ID] [--repeat N] [--versions N,N] [--concurrency N] [--cap USD] [--dry-run] [--data DIR] [--real DIR]
// A run without --only does TTS, STT (one variant), the Writing cleanup, then the report and the pairs file.

import { parseArgs } from "node:util";
import { fail, intArg } from "../cli.ts";
import { parseLevers, parseModels, parseVersions, pinnedProviders, runCleanup } from "../cleanup.ts";
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
/**
 * Dry-run estimate per call: the mean cost by model of this bench's v2 rows (cleanup-raw.jsonl, 2026-10-16). Version 3
 * prompts are about 1.3x the input (docs/research/cleanup-prompts.md, section 10), counted as 1.3x the whole call.
 */
const PLANNED_CLEANUP_USD: Record<string, number> = {
	"qwen3.8-27b@cerebras": 0.000609,
	"gemini-3.5-flash-lite": 0.000236,
	"claude-haiku-5.5": 0.000103,
	"gpt-6-luna": 0.000072,
	"deepseek-v4.1-flash": 0.000085,
};
const V3_COST_FACTOR = 1.3;

const { values } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		only: { type: "string" },
		concurrency: { type: "string", default: "16" },
		cap: { type: "string" },
		"dry-run": { type: "boolean", default: false },
		// This bench's folder: dictionary.json (a copy of kotoba-bench-v1's, so the prompt carries the same vocabulary), clips/, results/.
		data: { type: "string", default: Bun.env.KOTOBA_WRITING_DATA },
		// Cleanup only on the trap texts (questions and commands), for a re-run after a Writing prompt change.
		traps: { type: "boolean", default: false },
		// Comma-separated CLEANUP_MODELS keys for the cleanup pass; default every model.
		models: { type: "string" },
		// Comma-separated LEVERS keys (cleanup.ts), each its own variant; default the plain request.
		levers: { type: "string" },
		// Comma-separated prompt versions (cleanup.ts PROMPTS), each its own variant; default the shipped one.
		versions: { type: "string" },
		// Cleanup only on these comma-separated text ids (texts.ts), and N successful samples of each (keep rates).
		clips: { type: "string" },
		repeat: { type: "string", default: "1" },
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
const models = parseModels(values.models, fail);
const levers = parseLevers(values.levers, fail);
const versions = parseVersions(values.versions, "writing", fail);
const repeat = intArg(values, "repeat", 1)!;
const clipIds = values.clips?.split(",");
if (clipIds?.some((id) => !TEXTS.some((t) => t.id === id))) fail(`--clips: ids from writing/texts.ts`);

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
		await Promise.all([confirmTtsModel(), confirmModels([MAI], models.map((m) => m.model), pinnedProviders(models))]);
		console.log("models confirmed on OpenRouter");
	}
	const spent = await spentUsd(p.rawFiles);
	const budget = new Budget(runCap === undefined ? COST_CAP_USD : spent + runCap, spent);
	console.log(`spent so far (from raw files): $${spent.toFixed(4)}; this run stops past $${budget.cap.toFixed(4)} total`);
	if (runs("tts")) await runTts(p, clips, budget, Math.min(concurrency, TTS_CONCURRENCY), dryRun);

	const done = await synthesized(p, clips);
	const voiced = clips.filter((c) => done.has(c.id));
	const cleaned = voiced.filter((c) => (!values.traps || c.text.trap) && (!clipIds || clipIds.includes(c.id)));
	const versionFactor = versions.reduce((s, v) => s + (v >= 3 ? V3_COST_FACTOR : 1), 0);
	const cleanupUsdPerClip =
		repeat * versionFactor * Math.max(1, levers.length) * models.reduce((s, m) => s + (PLANNED_CLEANUP_USD[m.key] ?? 0), 0);
	if (dryRun && !voiced.length) {
		// Before TTS there is no audio to measure: plan from the text length.
		const sec = clips.reduce((s, c) => s + plannedSec(c), 0);
		const sttUsd = sec * LISTED_USD_PER_SEC[MAI]!;
		const planned = clips.filter((c) => (!values.traps || c.text.trap) && (!clipIds || clipIds.includes(c.id)));
		const calls = planned.length * models.length * versions.length * Math.max(1, levers.length) * repeat;
		console.log(`\nSTT plan: ${INPUT_VARIANT}, ${clips.length} calls, ~${(sec / 60).toFixed(1)} min audio, ~$${sttUsd.toFixed(3)}`);
		console.log(
			`Cleanup plan (Writing prompt): ${planned.length} clips, ${calls} calls, ` +
				`~$${(planned.length * cleanupUsdPerClip).toFixed(3)} at the planned cost per call`,
		);
	} else if (voiced.length && !budget.exceeded) {
		const audio = await prepareAudio(p, voiced);
		const ctx = { p, clips: voiced, audio, dict, budget, concurrency, dryRun, passthroughProbe: 0 };
		const variant = sttVariants(dict).find((v) => v.key === INPUT_VARIANT)!;
		if (runs("stt")) await runVariants(ctx, INPUT_VARIANT, [[variant, voiced]]);
		if (runs("cleanup") && !budget.exceeded) {
			if (dryRun) console.log(`  at most ~$${(cleaned.length * cleanupUsdPerClip).toFixed(3)} at the planned cost per call`);
			await runCleanup({ p, clips: cleaned, vocabulary: vocabulary(dict), budget, concurrency, dryRun, prompt: "writing", models, levers, repeat, versions });
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
