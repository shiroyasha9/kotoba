// kotoba-bench-v1 entry point.
// bun run bench [--limit N] [--only stt|cleanup|latency|report] [--probe N] [--concurrency N] [--dry-run] [--data DIR]
// A run without --only does the accuracy pass (STT, cleanup), then the sequential latency pass, then the report.

import { parseArgs } from "node:util";
import { fail, intArg } from "./cli.ts";
import { CLEANUP_MODELS, PINNED_PROVIDERS, runCleanup } from "./cleanup.ts";
import { loadClips, loadDictionary, paths, prepareAudio, vocabulary } from "./data.ts";
import { Budget, confirmModels, spentUsd } from "./openrouter.ts";
import { writeReport } from "./report.ts";
import { GROK, MAI, runLatency, runStt } from "./stt.ts";

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
		"dry-run": { type: "boolean", default: false },
		data: { type: "string", default: Bun.env.KOTOBA_BENCH_DATA },
	},
});

const only = values.only as Pass | undefined;
if (only && !PASSES.includes(only)) fail(`--only must be one of ${PASSES.join(", ")}`);
const limit = intArg(values, "limit", 1);
const passthroughProbe = intArg(values, "probe", 0)!;
const concurrency = intArg(values, "concurrency", 1)!;
const dryRun = values["dry-run"];
if (!values.data) fail("set KOTOBA_BENCH_DATA or pass --data DIR");
const runs = (pass: Pass) => !only || only === pass;

const p = paths(values.data);
const { clips, skipped } = await loadClips(p, limit);
const dict = await loadDictionary(p);
const edited = clips.filter((c) => c.refSource === "edited").length;
console.log(`data: ${p.dataDir}`);
console.log(`clips: ${clips.length} (edited ${edited})${limit ? `, limit ${limit}` : ""}; dictionary: ${dict.length} entries`);
for (const s of skipped) console.warn(`  skipped ${s}`);

if (only !== "report") {
	if (!dryRun) {
		await confirmModels([GROK, MAI], CLEANUP_MODELS.map((m) => m.model), PINNED_PROVIDERS);
		console.log("models confirmed on OpenRouter");
	}
	const audio = await prepareAudio(p, clips);
	const spent = await spentUsd(p.rawFiles);
	const budget = new Budget(COST_CAP_USD, spent);
	console.log(`spent so far (from raw files): $${spent.toFixed(4)} of $${COST_CAP_USD} cap`);
	if (budget.exceeded) {
		console.error("cost cap already reached; only the report will be rebuilt");
	} else {
		const stt = { p, clips, audio, dict, budget, concurrency, dryRun, passthroughProbe };
		if (runs("stt")) await runStt(stt);
		if (runs("cleanup") && !budget.exceeded) {
			await runCleanup({ p, clips, vocabulary: vocabulary(dict), budget, concurrency, dryRun });
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
