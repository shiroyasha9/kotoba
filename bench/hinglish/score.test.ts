import { describe, expect, test } from "bun:test";
import {
	casualLatin,
	deleteSchwa,
	foldLatin,
	romanize,
	scriptShare,
	tokens,
	translitTable,
	werDirect,
	werRomanized,
} from "./score.ts";
import { TEXTS } from "./texts.ts";

describe("scriptShare", () => {
	test("counts letters by script and skips marks, digits and punctuation", () => {
		const s = scriptShare("PR है, 42!");
		// P, R, ह (the matra in है is a mark, not a letter).
		expect(s.letters).toBe(3);
		expect(s.latin).toBeCloseTo(2 / 3);
		expect(s.devanagari).toBeCloseTo(1 / 3);
		expect(s.other).toBe(0);
	});

	test("flags Urdu output as other script", () => {
		expect(scriptShare("یہ ٹھیک ہے").other).toBe(1);
	});

	test("is all zero without letters", () => {
		expect(scriptShare("42 ...")).toEqual({ latin: 0, devanagari: 0, other: 0, letters: 0 });
	});
});

describe("tokens and folds", () => {
	test("folds common Hinglish spellings to one form", () => {
		expect(["nahin", "nahi", "nhi"].map(foldLatin)).toEqual(["nahi", "nahi", "nahi"]);
		expect(["zyada", "jyada", "jyaada"].map(foldLatin)).toEqual(["jyada", "jyada", "jyada"]);
		expect(["gayi", "gai"].map(foldLatin)).toEqual(["gai", "gai"]);
		expect(["woh", "vo", "wo"].map(foldLatin)).toEqual(["vo", "vo", "vo"]);
		expect(["pehle", "pahle"].map(foldLatin)).toEqual(["pehle", "pehle"]);
	});

	test("keeps Devanagari vowel signs, drops nukta and punctuation", () => {
		expect(tokens("ज़्यादा काम है।")).toEqual(["ज्यादा", "काम", "है"]);
	});

	test("drops fillers and lowercases", () => {
		expect(tokens("Um, PR merge KARO.")).toEqual(["pr", "merge", "karo"]);
	});
});

describe("transliteration", () => {
	test("deletes the word-final and medial schwa", () => {
		expect(deleteSchwa("कर")).toBe("कर्");
		expect(deleteSchwa("और")).toBe("और्");
		expect(deleteSchwa("करना")).toBe("कर्ना");
		expect(deleteSchwa("है")).toBe("है");
	});

	test("maps ICU diacritics to casual spelling", () => {
		expect(casualLatin("nahīṁ")).toBe("nahin");
		expect(casualLatin("śāyad")).toBe("shayad");
		expect(casualLatin("calō")).toBe("chalo");
		expect(casualLatin("kuch")).toBe("kuchh");
	});

	test(
		"ICU romanizes every Hinglish text's spoken form to its reference",
		async () => {
			const hinglish = TEXTS.filter((t) => t.set === "hinglish");
			const table = await translitTable(hinglish.map((t) => t.spoken));
			for (const t of hinglish) {
				const got = tokens(romanize(t.spoken, table)).join(" ");
				expect(`${t.id}: ${got}`).toBe(`${t.id}: ${tokens(t.reference).join(" ")}`);
			}
		},
		60_000,
	);
});

describe("WER", () => {
	test("direct WER counts Devanagari words in Hinglish output as errors; romanized WER does not", async () => {
		const ref = "ye PR abhi merge mat karna";
		const hyp = "ये PR अभी merge मत करना";
		const table = await translitTable([hyp]);
		expect(werDirect(ref, hyp)).toEqual({ errors: 4, refWords: 6 });
		expect(werRomanized(ref, hyp, table)).toEqual({ errors: 0, refWords: 6 });
	}, 60_000);
});

describe("texts", () => {
	test("ids are unique and each set has its size", () => {
		expect(new Set(TEXTS.map((t) => t.id)).size).toBe(TEXTS.length);
		expect(TEXTS.filter((t) => t.set === "hinglish")).toHaveLength(30);
		expect(TEXTS.filter((t) => t.set === "hindi")).toHaveLength(10);
	});

	test("Hinglish references are Latin only; Hindi references are Devanagari only", () => {
		for (const t of TEXTS) {
			const s = scriptShare(t.reference);
			if (t.set === "hinglish") expect(s.latin).toBe(1);
			else expect(s.devanagari).toBe(1);
		}
	});
});
