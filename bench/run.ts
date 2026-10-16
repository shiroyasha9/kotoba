// kotoba-bench-v1 entry point.
// bun run bench [--limit N] [--only stt|cleanup|latency|report] [--prompt code|writing] [--models KEY,KEY] [--levers KEY,KEY] [--versions N,N] [--probe N] [--concurrency N]
//   [--cap USD] [--dry-run] [--data DIR]
// A run without --only does the accuracy pass (STT, cleanup), then the sequential latency pass, then the report.

import { parseArgs } from "node:util";
import { fail, intArg } from "./cli.ts";
import { type CleanupPrompt, parseLevers, parseModels, parseVersions, pinnedProviders, runCleanup } from "./cleanup.ts";
import { loadClips, loadDictionary, paths, prepareAudio, vocabulary } from "./data.ts";
import { Budget, confirmModels, spentUsd } from "./openrouter.ts";
import { writeReport } from "./report.ts";
import { GROK, MAI, runLatency, runStt } from "./stt.ts";

/** Default cap on all spend recorded in the raw files, across runs. `--cap` sets a per-run cap instead. */
const COST_CAP_USD = 2;
const PASSES = ["stt", "cleanup", "latency", "report"] as const;
type Pass = (typeof PASSES)[number];

const { values } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		limit: { type: "string" },
		only: { type: "string" },
		// Clips each passthrough STT variant runs on before the same-text gate; 0 = every clip.
		probe: { type: "string", default: "20" },
		// Requests in flight for the accuracy pass; its latency is contended and not used for gates.
		concurrency: { type: "string", default: "100" },
		// USD this run may add on top of what the raw files already record (the owner's go names it).
		cap: { type: "string" },
		// The cleanup prompt: kotoba's Code prompt on the cleanup sets, or its Writing prompt on clips from Writing apps.
		prompt: { type: "string", default: "code" },
		// Cleanup pass only: comma-separated CLEANUP_MODELS keys (default all), LEVERS keys (default none) and prompt versions
		// (default the shipped one).
		models: { type: "string" },
		levers: { type: "string" },
		versions: { type: "string" },
		"dry-run": { type: "boolean", default: false },
		data: { type: "string", default: Bun.env.KOTOBA_BENCH_DATA },
	},
});

const only = values.only as Pass | undefined;
if (only && !PASSES.includes(only)) fail(`--only must be one of ${PASSES.join(", ")}`);
const limit = intArg(values, "limit", 1);
const passthroughProbe = intArg(values, "probe", 0)!;
const concurrency = intArg(values, "concurrency", 1)!;
const runCap = values.cap === undefined ? undefined : Number(values.cap);
if (runCap !== undefined && !(runCap > 0)) fail("--cap must be a positive number of USD");
const dryRun = values["dry-run"];
const prompt = values.prompt as CleanupPrompt;
if (prompt !== "code" && prompt !== "writing") fail("--prompt must be code or writing");
if (!values.data) fail("set KOTOBA_BENCH_DATA or pass --data DIR");
const runs = (pass: Pass) => !only || only === pass;
const models = parseModels(values.models, fail);
const levers = parseLevers(values.levers, fail);
const versions = parseVersions(values.versions, prompt, fail);

const p = paths(values.data);
const { clips, skipped } = await loadClips(p, limit);
const dict = await loadDictionary(p);
const edited = clips.filter((c) => c.refSource === "edited").length;
console.log(`data: ${p.dataDir}`);
console.log(`clips: ${clips.length} (edited ${edited})${limit ? `, limit ${limit}` : ""}; dictionary: ${dict.length} entries`);
for (const s of skipped) console.warn(`  skipped ${s}`);

if (only !== "report") {
	if (!dryRun) {
		await confirmModels([GROK, MAI], models.map((m) => m.model), pinnedProviders(models));
		console.log("models confirmed on OpenRouter");
	}
	const audio = await prepareAudio(p, clips);
	const spent = await spentUsd(p.rawFiles);
	const budget = new Budget(runCap === undefined ? COST_CAP_USD : spent + runCap, spent);
	console.log(`spent so far (from raw files): $${spent.toFixed(4)}; this run stops past $${budget.cap.toFixed(4)} total`);
	if (budget.exceeded) {
		console.error("cost cap already reached; only the report will be rebuilt");
	} else {
		const stt = { p, clips, audio, dict, budget, concurrency, dryRun, passthroughProbe };
		if (runs("stt")) await runStt(stt);
		if (runs("cleanup") && !budget.exceeded) {
			await runCleanup({ p, clips, vocabulary: vocabulary(dict), budget, concurrency, dryRun, prompt, models, levers, versions });
		}
		if (runs("latency") && !budget.exceeded) await runLatency(stt);
		console.log(`spent total: $${budget.total.toFixed(4)}`);
	}
}

if (dryRun && only !== "report") {
	console.log("\ndry run: no requests sent, report not written");
} else {
	await writeReport(p, clips, dict);
	console.log(`\nreport: ${p.report}`);
}
