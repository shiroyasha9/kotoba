import { describe, expect, test } from "bun:test";
import {
	type PoolTerm,
	type WisprRow,
	appKeyterms,
	buildDictionary,
	countTerm,
	firstKeyterms,
	randomTerms,
	rankedTerms,
	useScore,
	useTimes,
} from "./lists.ts";

const DAY = 86_400_000;
const NOW = Date.UTC(2026, 9, 10);
const term = (t: string, addedAt: number | null = null, pinned = false): PoolTerm => ({ term: t, addedAt, pinned, real: true });

describe("countTerm", () => {
	test("matches whole phrases, case-insensitive", () => {
		expect(countTerm("Zod and zod, not zodiac", "zod")).toBe(2);
		expect(countTerm("run /grill-me then Stacked PRs", "/grill-me")).toBe(1);
		expect(countTerm("stacked prs", "Stacked PRs")).toBe(1);
		expect(countTerm("gpt-5.6-luna.", "gpt-5.6-luna")).toBe(1);
	});
});

describe("useScore", () => {
	test("counts only dictations before now and halves every 30 days", () => {
		expect(useScore([NOW - 30 * DAY, NOW + DAY], NOW)).toBeCloseTo(0.5);
		expect(useScore([NOW - 60 * DAY, NOW - 30 * DAY], NOW)).toBeCloseTo(1);
		expect(useScore([NOW], NOW)).toBe(0);
		expect(useScore(undefined, NOW)).toBe(0);
	});
});

describe("rankedTerms", () => {
	const history = [
		{ at: NOW - 40 * DAY, text: "old zod talk" },
		{ at: NOW - 2 * DAY, text: "Mastra Mastra" },
		{ at: NOW - DAY, text: "Mastra again" },
		{ at: NOW + DAY, text: "Braintrust later" },
	];
	const pool = [term("Braintrust"), term("zod"), term("Mastra"), term("Lings", NOW - 3 * DAY), term("pinned", null, true), term("Codex")];
	const uses = useTimes(pool.map((t) => t.term), history);

	test("pinned, then recent, then by use score, then pool order", () => {
		expect(rankedTerms(pool, uses, NOW, 10)).toEqual(["pinned", "Lings", "Mastra", "zod", "Braintrust", "Codex"]);
	});

	test("cuts at the limit; a later use and a later add do not count", () => {
		expect(rankedTerms(pool, uses, NOW, 3)).toEqual(["pinned", "Lings", "Mastra"]);
		expect(rankedTerms(pool, uses, NOW - 4 * DAY, 3)).toEqual(["pinned", "zod", "Braintrust"]);
	});
});

describe("rankedTerms, use first", () => {
	test("terms with earlier use go before recently added ones", () => {
		const pool = [term("new", NOW - DAY), term("used")];
		const uses = useTimes(["new", "used"], [{ at: NOW - 2 * DAY, text: "used" }]);
		expect(rankedTerms(pool, uses, NOW, 1)).toEqual(["new"]);
		expect(rankedTerms(pool, uses, NOW, 1, true)).toEqual(["used"]);
	});
});

describe("appKeyterms", () => {
	const row = (phrase: string, extra: Partial<WisprRow> = {}): WisprRow => ({
		phrase,
		replacement: null,
		createdAt: "2026-10-01 12:00:47.050 +00:00",
		isDeleted: 0,
		isStarred: 0,
		isSnippet: 0,
		source: "manual",
		observedSource: null,
		...extra,
	});

	test("terms in row order, then rule spellings, without case-insensitive duplicates", () => {
		const rows = [
			row("zod"),
			row("btw", { replacement: "by the way" }),
			row("Zod"),
			row("Keepsa", { source: "user_edits", observedSource: "Kipsa" }),
			row("gone", { isDeleted: 1 }),
			row("sig", { isSnippet: 1 }),
			row("jeb", { replacement: "jev" }),
			row("jev"),
		];
		expect(appKeyterms(rows)).toEqual(["zod", "Keepsa", "jev", "by the way"]);
	});

	test("stops at the cap and skips terms over 50 characters", () => {
		expect(firstKeyterms(["a", "x".repeat(51), "b", "c"], 2)).toEqual(["a", "b"]);
	});
});

describe("buildDictionary", () => {
	test("keeps the owner's terms first, fills to the size, and is reproducible", () => {
		const real = Array.from({ length: 30 }, (_, i) => term(`real${i}`, NOW - i * DAY));
		const distractors = Array.from({ length: 400 }, (_, i) => `d${i}`);
		const dict = buildDictionary(real, distractors);
		expect(dict).toHaveLength(300);
		expect(dict.slice(0, 30)).toEqual(real);
		expect(dict.slice(30).every((t) => !t.real && t.addedAt === null)).toBe(true);
		expect(buildDictionary(real, distractors)).toEqual(dict);
		const r = randomTerms(dict, 25, 7);
		expect(new Set(r).size).toBe(25);
		expect(randomTerms(dict, 25, 7)).toEqual(r);
	});
});
