import { describe, expect, test } from "bun:test";
import { align, normalize, shortDiff, termRecall, wer } from "./score.ts";

describe("normalize", () => {
	test("lowercases, strips punctuation and drops fillers", () => {
		expect(normalize("Um, so I think — uh — we're DONE!")).toEqual(["so", "i", "think", "were", "done"]);
	});

	test("keeps punctuation inside identifier-shaped tokens", () => {
		expect(normalize("Open src/auth.ts, then run `bun test --watch`.")).toEqual([
			"open",
			"src/auth.ts",
			"then",
			"run",
			"bun",
			"test",
			"--watch",
		]);
		expect(normalize("Edit .env and user_id on localhost:3000.")).toEqual([
			"edit",
			".env",
			"and",
			"user_id",
			"on",
			"localhost:3000",
		]);
	});

	test("collapses whitespace", () => {
		expect(normalize("  a \n\t b  ")).toEqual(["a", "b"]);
	});
});

describe("wer", () => {
	test("identical text after normalization scores zero", () => {
		expect(wer("Hello, world.", "hello world").errors).toBe(0);
	});

	test("counts substitutions, deletions and insertions", () => {
		const w = wer("The cat sat on the mat", "the bat sat on mat today");
		expect(w.refWords).toBe(6);
		expect(w.errors).toBe(3);
		// The only distance-2 path: delete "b", insert "e".
		expect(wer("a b c d", "a c d e").ops.filter((o) => o.op !== "ok")).toEqual([
			{ op: "del", ref: "b" },
			{ op: "ins", hyp: "e" },
		]);
		expect(wer("x y", "x z").ops[1]).toEqual({ op: "sub", ref: "y", hyp: "z" });
	});

	test("empty hypothesis deletes every reference word", () => {
		expect(wer("one two three", "").errors).toBe(3);
	});

	test("fillers on either side do not count", () => {
		expect(wer("so um we ship", "uh so we ship hmm").errors).toBe(0);
	});
});

describe("align and shortDiff", () => {
	test("edit distance matches the classic kitten/sitting case on tokens", () => {
		const ops = align("k i t t e n".split(" "), "s i t t i n g".split(" "));
		expect(ops.filter((o) => o.op !== "ok")).toHaveLength(3);
	});

	test("renders substitutions, deletions and insertions", () => {
		const diff = shortDiff(wer("fix the auth bug now", "fix the off bug").ops);
		expect(diff).toBe("·· [auth→off] · -now");
	});
});

describe("termRecall", () => {
	const dict = ["OpenRouter", "Claude Code"];

	test("counts technical tokens found exactly, case-sensitive", () => {
		const r = termRecall(
			"Run bun test in src/score.ts with --watch, then ask Claude Code about getUserId and v2.",
			"run bun test in src/score.ts with --watch then ask claude code about getUserID and v2",
			dict,
		);
		// technical: src/score.ts, --watch, Claude, Code, getUserId, v2
		expect(r.total).toBe(6);
		expect(r.hits).toBe(3);
		expect(r.missed).toEqual(["Claude", "Code", "getUserId"]);
	});

	test("backticked tokens and dictionary terms count; repeats need repeats", () => {
		const r = termRecall("Use `fetch` and OpenRouter, OpenRouter.", "Use fetch and OpenRouter.", dict);
		expect(r.total).toBe(3);
		expect(r.hits).toBe(2);
	});

	test("no technical tokens gives an empty denominator", () => {
		expect(termRecall("plain words only", "plain words", dict)).toEqual({ hits: 0, total: 0, missed: [] });
	});
});
