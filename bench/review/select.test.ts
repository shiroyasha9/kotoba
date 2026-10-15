import { describe, expect, test } from "bun:test";
import { DURATION_BUCKETS, type ManifestRow, durationBucket } from "../data.ts";
import type { RawRow } from "../openrouter.ts";
import { type Candidate, allocate, candidates, reviewOrder, selectClips, wordDistance } from "./select.ts";

const DURATIONS = [3, 15, 30, 60];

/** 120 clips, 30 per duration bucket; every 7th is user-edited; every 3rd has STT variants that disagree. */
function fixture(): { manifest: ManifestRow[]; stt: RawRow[] } {
	const manifest: ManifestRow[] = [];
	const stt: RawRow[] = [];
	for (let i = 0; i < 120; i++) {
		const id = `clip-${String(i).padStart(3, "0")}`;
		const text = `open the file number ${i} and fix it`;
		manifest.push({
			transcriptEntityId: id,
			timestamp: null,
			app: "com.cmuxterm.app",
			url: null,
			duration: DURATIONS[i % 4]! + (i % 5) / 10,
			numWords: null,
			e2eLatency: null,
			clientNetworkLatency: null,
			asrText: text,
			formattedText: text,
			editedText: i % 7 === 0 ? `${text} please` : text,
			pastedText: text,
		});
		stt.push({ variant: "mai+phraseList", clipId: id, ok: true, text, cost: null });
		stt.push({ variant: "grok+keyterms", clipId: id, ok: true, text: i % 3 === 0 ? "something else entirely" : text, cost: null });
	}
	return { manifest, stt };
}

describe("wordDistance", () => {
	test("ignores case and edge punctuation, keeps identifiers, and is symmetric", () => {
		expect(wordDistance("Fix auth.ts, please.", "fix auth.ts please")).toBe(0);
		expect(wordDistance("fix auth.ts", "fix authts")).toBe(0.5);
		expect(wordDistance("a b c d", "a x c")).toBe(wordDistance("a x c", "a b c d"));
		expect(wordDistance("a b c d", "a x c")).toBe(0.5);
	});
});

describe("allocate", () => {
	test("splits evenly and hands spare slots of a small bucket to the others", () => {
		expect(allocate({ "<10 s": 86, "10-20 s": 63, "20-40 s": 50, ">40 s": 35 }, 50)).toEqual({
			"<10 s": 12,
			"10-20 s": 12,
			"20-40 s": 13,
			">40 s": 13,
		});
		const small = allocate({ "<10 s": 40, "10-20 s": 40, "20-40 s": 40, ">40 s": 5 }, 50);
		expect(small[">40 s"]).toBe(5);
		expect(Object.values(small).reduce((s, v) => s + v, 0)).toBe(50);
	});
});

describe("selectClips", () => {
	const { manifest, stt } = fixture();
	const pool = candidates(manifest, stt);

	test("excludes user-edited clips and clips without a mai+phraseList transcript", () => {
		const noMai = candidates(manifest, stt.filter((r) => r.clipId !== "clip-001" || r.variant !== "mai+phraseList"));
		expect(pool.some((c) => c.id === "clip-000" || c.id === "clip-007")).toBe(false);
		expect(pool).toHaveLength(120 - 18);
		expect(noMai.some((c) => c.id === "clip-001")).toBe(false);
	});

	test("is deterministic for a seed and changes with the seed", () => {
		const ids = (seed: number) => selectClips(pool, 20, seed).map((c) => c.id);
		expect(ids(1)).toEqual(ids(1));
		expect(ids(1)).not.toEqual(ids(2));
		// Pinned: the owner's review-set.json was chosen with this code.
		expect(selectClips(pool, 8, 1).map((c) => c.id)).toEqual([
			"clip-044",
			"clip-075",
			"clip-045",
			"clip-030",
			"clip-039",
			"clip-016",
			"clip-057",
			"clip-102",
		]);
	});

	test("draws an equal share from each duration bucket", () => {
		const picked = selectClips(pool, 20, 1);
		expect(new Set(picked.map((c) => c.id)).size).toBe(20);
		for (const b of DURATION_BUCKETS) expect(picked.filter((c) => durationBucket(c.duration) === b)).toHaveLength(5);
	});

	test("favours clips where the variants disagree", () => {
		const disagreeing = pool.filter((c) => c.disagreement > 0).length / pool.length;
		let picked = 0;
		let total = 0;
		for (let seed = 1; seed <= 20; seed++) {
			const s = selectClips(pool, 20, seed);
			picked += s.filter((c) => c.disagreement > 0).length;
			total += s.length;
		}
		expect(picked / total).toBeGreaterThan(disagreeing * 1.5);
	});
});

test("reviewOrder: shortest first, clipId breaks ties, input untouched", () => {
	const c = (id: string, duration: number) => ({ id, duration }) as Candidate;
	const input = [c("b", 12), c("c", 3.5), c("a", 12), c("d", 40)];
	expect(reviewOrder(input).map((x) => x.id)).toEqual(["c", "a", "b", "d"]);
	expect(input.map((x) => x.id)).toEqual(["b", "c", "a", "d"]);
});
