// List-size bench: does a shorter MAI phrase list help or hurt?
// bun run termcap [--only lists|stt|latency|route|report] [--limit N] [--concurrency N] [--cap USD] [--dry-run]
//   [--data DIR] [--out DIR]
// `--data` is the kotoba-bench-v1 folder (clips, audio, the `mai` and `mai+phraseList` rows, reused);
// `--out` holds the Wispr exports (README.md), the lists, this bench's raw rows and its report.

import { join } from "node:path";
import { parseArgs } from "node:util";
import { $ } from "bun";
import { fail, intArg } from "../cli.ts";
import {
	type AudioInfo,
	type Clip,
	durationBucket,
	loadClips,
	loadDictionary,
	loadReferences,
	paths,
	prepareAudio,
	seededSample,
} from "../data.ts";
import { Budget, confirmModels, okRowsByVariant, readJsonl, runCalls, spentUsd } from "../openrouter.ts";
import { LATENCY_CLIPS, LISTED_USD_PER_SEC, MAI, type SttRow, type SttVariant, biasTerms, transcribe } from "../stt.ts";
import {
	CONDITIONS,
	APP_CAP,
	DICTIONARY_SIZE,
	DISTRACTOR_CANDIDATES,
	LATENCY_KEYS,
	type Condition,
	type ListRow,
	type PoolTerm,
	type WisprRow,
	appKeyterms,
	buildDictionary,
	countTerm,
	firstKeyterms,
	neededCoverage,
	randomTerms,
	rankedTerms,
	seedOf,
	termcapPaths,
	useTimes,
	wisprTime,
} from "./lists.ts";
import { writeTermcapReport } from "./report.ts";

/** Cap on all spend recorded in this bench's raw files, across runs (the owner's go: stop past $1.00). */
const COST_CAP_USD = 1;
const PASSES = ["lists", "stt", "latency", "route", "report"] as const;
type Pass = (typeof PASSES)[number];

const { values } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		only: { type: "string" },
		limit: { type: "string" },
		concurrency: { type: "string", default: "50" },
		cap: { type: "string" },
		"dry-run": { type: "boolean", default: false },
		data: { type: "string", default: Bun.env.KOTOBA_BENCH_DATA },
		out: { type: "string", default: Bun.env.KOTOBA_TERMCAP_DATA },
	},
});

const only = values.only as Pass | undefined;
if (only && !PASSES.includes(only)) fail(`--only must be one of ${PASSES.join(", ")}`);
const limit = intArg(values, "limit", 1);
const concurrency = intArg(values, "concurrency", 1)!;
const runCap = values.cap === undefined ? undefined : Number(values.cap);
if (runCap !== undefined && !(runCap > 0)) fail("--cap must be a positive number of USD");
const dryRun = values["dry-run"];
if (!values.data) fail("set KOTOBA_BENCH_DATA or pass --data DIR");
if (!values.out) fail("set KOTOBA_TERMCAP_DATA or pass --out DIR");
const runs = (pass: Pass) => !only || only === pass;

const bp = paths(values.data);
const tp = termcapPaths(values.out);
const { clips: allClips } = await loadClips(bp);
const clips = limit ? allClips.slice(0, limit) : allClips;
const dict = await loadDictionary(bp);
const ownerRefs = await loadReferences(bp);
/** The owner's hand-corrected reference when there is one, else the bench reference. */
const refOf = (c: Clip) => ownerRefs.get(c.id)?.text ?? c.reference;

// --- Lists --------------------------------------------------------------

const wisprDict: WisprRow[] = await Bun.file(tp.wisprDictionary).json();
const history = ((await Bun.file(tp.wisprHistory).json()) as { timestamp: string; text: string | null }[])
	.filter((h) => h.text)
	.map((h) => ({ at: wisprTime(h.timestamp), text: h.text! }));

/** Earliest live Wispr entry with this phrase or replacement: when the owner added the term. */
function added(term: string): { addedAt: number | null; pinned: boolean } {
	const rows = wisprDict.filter((r) => !r.isDeleted && (r.phrase === term || r.replacement === term));
	const times = rows.map((r) => wisprTime(r.createdAt));
	return { addedAt: times.length ? Math.min(...times) : null, pinned: rows.some((r) => r.isStarred) };
}

const real: PoolTerm[] = appKeyterms(wisprDict).map((term) => ({ term, ...added(term), real: true }));
const allRefs = allClips.map(refOf);

/** Distractor candidates, frozen on the first run: the list above plus the type names in kotoba's Swift sources. */
async function distractorCandidates(): Promise<string[]> {
	const file = Bun.file(tp.distractors);
	if (await file.exists()) return file.json();
	const repo = join(import.meta.dir, "../..");
	const sources = (await $`git -C ${repo} ls-files -- '*.swift'`.text()).split("\n").filter(Boolean);
	const types = new Set<string>();
	for (const f of sources) {
		for (const m of (await Bun.file(join(repo, f)).text()).matchAll(/\b(?:struct|class|enum|actor|protocol) ([A-Z][A-Za-z0-9]{3,})/g)) {
			types.add(m[1]!);
		}
	}
	const list = [...new Set([...DISTRACTOR_CANDIDATES, ...[...types].sort()])];
	await Bun.write(file, JSON.stringify(list, null, 2));
	return list;
}
const realLower = new Set(real.map((t) => t.term.toLowerCase()));
const distractors = (await distractorCandidates()).filter(
	(d) => !realLower.has(d.toLowerCase()) && allRefs.every((r) => countTerm(r, d) === 0),
);
const dictionary = buildDictionary(real, distractors);
const uses = useTimes(dictionary.map((t) => t.term), history);
const stored = dictionary.map((t) => t.term);

function listFor(clip: Clip, c: Condition): string[] {
	switch (c.pick) {
		case "app":
			return real.map((t) => t.term);
		case "first":
			return firstKeyterms(stored, c.size);
		case "random":
			return randomTerms(dictionary, c.size, seedOf(`${clip.id}:${c.size}`));
		case "ranked":
			return rankedTerms(dictionary, uses, wisprTime(clip.timestamp!), c.size, c.useFirst);
	}
}

/** condition -> clip id -> the terms sent. */
const lists = new Map<string, Map<string, string[]>>();
const listOf = (condition: string, clipId: string) => lists.get(condition)?.get(clipId) ?? [];
/** Scored offline only (no paid pass): needed-term coverage of other sizes and of the use-first order. */
const OFFLINE: Condition[] = [
	{ key: "ranked-50", size: 50, pick: "ranked" },
	{ key: "random-50", size: 50, pick: "random" },
	{ key: "use-first-25", size: 25, pick: "ranked", useFirst: true },
	{ key: "use-first-50", size: 50, pick: "ranked", useFirst: true },
	{ key: "ranked-100", size: 100, pick: "ranked" },
];
for (const clip of clips) {
	const set = (condition: string, terms: string[]) =>
		lists.set(condition, (lists.get(condition) ?? new Map()).set(clip.id, terms));
	for (const c of CONDITIONS) set(c.key, listFor(clip, c));
	for (const c of OFFLINE) set(c.key, listFor(clip, c));
	set("bench-33", biasTerms(dict));
	set("none", []);
}
await Bun.write(tp.dictionary, JSON.stringify({ dictionary, distractorsKept: distractors.length }, null, 2));
const listRows: ListRow[] = [...lists].flatMap(([condition, byClip]) =>
	[...byClip].map(([clipId, terms]) => ({ clipId, condition, terms })),
);
await Bun.write(tp.lists, listRows.map((r) => JSON.stringify(r)).join("\n") + "\n");
console.log(`data: ${bp.dataDir}\nout: ${tp.out}`);
console.log(
	`clips: ${clips.length}; owner references: ${clips.filter((c) => ownerRefs.has(c.id)).length}; Wispr history rows: ${history.length}`,
);
console.log(
	`dictionary: today's ${real.length} terms + ${dictionary.length - real.length} distractors (of ${distractors.length} absent from every reference)`,
);

const realTerms = real.map((t) => t.term);
for (const key of lists.keys()) {
	const { inList, want } = neededCoverage(clips, refOf, realTerms, (id) => listOf(key, id));
	console.log(`  ${key.padEnd(12)} needed-term occurrences in the list ${String(inList).padStart(3)}, left out ${String(want - inList).padStart(3)}`);
}

// --- Paid passes --------------------------------------------------------

const variant = (key: string, terms: string[]): SttVariant<string> => ({
	key,
	model: MAI,
	...(terms.length ? { providerOptions: { azure: { phraseList: { phrases: terms } } } } : {}),
});
type Job = { v: SttVariant<string>; c: Clip };
const secsOf = (audio: Map<string, AudioInfo>, jobs: Job[]) => jobs.reduce((s, j) => s + (audio.get(j.c.id)?.durationSec ?? 0), 0);
const listedUsd = (sec: number) => `~$${(sec * LISTED_USD_PER_SEC[MAI]!).toFixed(3)} at listed price`;
const shortest = <T>(items: T[], clip: (x: T) => Clip, audio: Map<string, AudioInfo>) =>
	items.reduce((a, b) => (audio.get(clip(b).id)!.durationSec < audio.get(clip(a).id)!.durationSec ? b : a));

async function pending(file: string, jobs: Job[]): Promise<Job[]> {
	const ok = okRowsByVariant(await readJsonl<SttRow>(file));
	return jobs.filter((j) => !ok.get(j.v.key)?.has(j.c.id));
}

/** Runs `jobs` after one probe call that measures the real price; stops when the projection passes the cap. */
async function pass(label: string, file: string, jobs: Job[], audio: Map<string, AudioInfo>, budget: Budget, lanes: number) {
	const sec = secsOf(audio, jobs);
	console.log(`\n${label}: ${jobs.length} calls pending, ${(sec / 60).toFixed(1)} min audio, ${listedUsd(sec)}`);
	if (dryRun || !jobs.length || budget.exceeded) return;
	const sink = { out: file, budget };
	const call = ({ v, c }: Job) => transcribe(bp, sink, { variant: v, clip: c, info: audio.get(c.id)!, format: "flac" });
	const [first, ...rest] = jobs;
	const probe = await call(first!);
	if (!probe.ok) fail(`probe call failed: ${probe.status} ${probe.error ?? ""}`);
	if (probe.cost === null) fail("probe call returned no usage.cost, so the cap cannot be checked");
	const rate = probe.cost / Math.max(1, probe.audioSec);
	const projected = rate * secsOf(audio, rest);
	console.log(`  probe: $${(rate * 3600).toFixed(3)}/audio-hour; projected $${projected.toFixed(3)}, total would be $${(budget.total + projected).toFixed(3)} of $${budget.cap.toFixed(2)}`);
	if (budget.total + projected > budget.cap) fail("projected spend passes the cap: stopped before the pool, report to the lead");
	await runCalls(label, rest, lanes, budget, call, ({ v, c }) => `${v.key} ${c.id}`);
	if (budget.exceeded) fail(`cost cap hit at $${budget.total.toFixed(4)}`);
}

/**
 * Finds the largest list the route accepts: first-N lists of the 300-term dictionary on the shortest clip,
 * by bisection between 100 and 300, then the last 100 terms alone (a rejection there points at content, not count).
 */
async function runRoute(audio: Map<string, AudioInfo>, budget: Budget): Promise<void> {
	const clip = shortest(clips, (c) => c, audio);
	const send = async (key: string, terms: string[]) => {
		const row = await transcribe(bp, { out: tp.routeRaw, budget }, { variant: variant(key, terms), clip, info: audio.get(clip.id)!, format: "flac" });
		console.log(`  ${key}: ${terms.length} terms -> ${row.status}`);
		return row.ok;
	};
	console.log(`\nroute limit on ${clip.id} (${audio.get(clip.id)!.durationSec.toFixed(1)} s)`);
	let ok = APP_CAP;
	let bad = DICTIONARY_SIZE;
	while (bad - ok > 1 && !budget.exceeded) {
		const mid = Math.floor((ok + bad) / 2);
		if (await send(`route-first-${mid}`, stored.slice(0, mid))) ok = mid;
		else bad = mid;
	}
	console.log(`  largest accepted: ${ok}; smallest rejected: ${bad}`);
	await send("route-last-100", stored.slice(-APP_CAP));
}

if (only === "route" && !dryRun) {
	const audio = await prepareAudio(bp, clips);
	const spent = await spentUsd(tp.rawFiles);
	await runRoute(audio, new Budget(COST_CAP_USD, spent));
}

if (runs("stt") || runs("latency")) {
	if (!dryRun) {
		await confirmModels([MAI], [], []);
		console.log("model confirmed on OpenRouter");
	}
	const audio = await prepareAudio(bp, clips);
	const spent = await spentUsd(tp.rawFiles);
	const budget = new Budget(runCap === undefined ? COST_CAP_USD : spent + runCap, spent);
	console.log(`spent so far (this bench's raw files): $${spent.toFixed(4)}; this run stops past $${budget.cap.toFixed(4)} total`);

	let accuracy = await pending(
		tp.sttRaw,
		// Interleaved by clip, so a stop leaves every condition with similar coverage.
		clips.flatMap((c) => CONDITIONS.map((k) => ({ v: variant(k.key, listOf(k.key, c.id)), c }))),
	);
	const bucket = clips.filter((c) => {
		const d = audio.get(c.id)?.durationSec;
		return d !== undefined && durationBucket(d) === "10-20 s";
	});
	// The bench's latency clips; the condition order rotates by one on each clip.
	let latency = await pending(
		tp.latencyRaw,
		seededSample(bucket, LATENCY_CLIPS).flatMap((c, i) =>
			LATENCY_KEYS.map((_, k) => LATENCY_KEYS[(i + k) % LATENCY_KEYS.length]!).map((key) => ({
				v: variant(key, listOf(key, c.id)),
				c,
			})),
		),
	);
	// The route's phrase-list limit is not published: one call with the 300-term list first, unless a 400 is on disk.
	const rejected = [...(await readJsonl<SttRow>(tp.sttRaw)), ...(await readJsonl<SttRow>(tp.routeRaw))].some(
		(r) => r.status === 400 && /^(all|route-first)-(\d+)$/.test(r.variant) && Number(r.variant.split("-").at(-1)) <= DICTIONARY_SIZE,
	);
	const over = accuracy.filter((j) => j.v.key === "all-300");
	if (!rejected && !dryRun && runs("stt") && over.length === clips.length && !budget.exceeded) {
		const check = shortest(over, (j) => j.c, audio);
		const row = await transcribe(bp, { out: tp.sttRaw, budget }, { variant: check.v, clip: check.c, info: audio.get(check.c.id)!, format: "flac" });
		console.log(`\nroute check, 300 terms: ${row.status} ${row.ok ? "accepted" : (row.error ?? "")}`);
		accuracy = accuracy.filter((j) => j !== check);
		if (!row.ok) {
			accuracy = accuracy.filter((j) => j.v.key !== "all-300");
			latency = latency.filter((j) => j.v.key !== "all-300");
		}
	} else if (rejected) {
		console.log("\nroute rejected a list of 300 or fewer terms earlier: all-300 is skipped");
		accuracy = accuracy.filter((j) => j.v.key !== "all-300");
		latency = latency.filter((j) => j.v.key !== "all-300");
	}
	if (dryRun) {
		const sec = secsOf(audio, [...(runs("stt") ? accuracy : []), ...(runs("latency") ? latency : [])]);
		console.log(`\nplan total: ${listedUsd(sec)}, cap $${budget.cap.toFixed(2)}`);
	}
	if (runs("stt")) await pass("accuracy pass", tp.sttRaw, accuracy, audio, budget, concurrency);
	if (runs("latency")) await pass("latency pass (sequential)", tp.latencyRaw, latency, audio, budget, 1);
	console.log(`spent total: $${budget.total.toFixed(4)}`);
}

if (only === "route") {
	console.log("\nroute rows in results/route-raw.jsonl; report not written");
} else if (dryRun || only === "lists") {
	console.log("\nno requests sent, report not written");
} else {
	await writeTermcapReport({ bp, tp, clips, refOf, owner: new Set(ownerRefs.keys()), real, dictionary, lists: listOf, offline: OFFLINE.map((c) => c.key), concurrency });
	console.log(`\nreport: ${tp.report}`);
}

