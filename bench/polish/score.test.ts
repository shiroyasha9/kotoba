import { describe, expect, test } from "bun:test";
import { badChars, codeTokens, htmlToText, missingTokens, newTokens, percentile, stratified, wordCount } from "./score.ts";

describe("htmlToText", () => {
	test("lists become dash and numbered lines", () => {
		expect(htmlToText("Do this:<ul><li>one</li><li>two</li></ul>Then<ol><li>a</li><li>b</li></ol>")).toBe(
			"Do this:\n\n- one\n- two\nThen\n\n1. a\n2. b",
		);
	});
});

describe("codeTokens", () => {
	test("finds identifiers, paths, flags, commands and numbers, not plain words", () => {
		const tokens = codeTokens("Open src/billing/webhook.ts, run bun test --watch and /grill-me on PTE v1.2 with useState. Fine.");
		expect(tokens).toEqual(["src/billing/webhook.ts", "--watch", "/grill-me", "PTE", "v1.2", "useState"]);
	});

	test("ignores trailing punctuation and keeps backticked spans", () => {
		expect(codeTokens("Check `make check` and TOEIC.")).toEqual(["make check", "TOEIC"]);
	});
});

describe("missingTokens and newTokens", () => {
	test("a non-breaking hyphen still counts as the token", () => {
		expect(missingTokens("use gpt-oss-120b", "use gpt\u2011oss\u2011120b")).toEqual([]);
		expect(badChars("gpt\u2011oss")).toBe(1);
	});

	test("a token inside a longer token does not count", () => {
		expect(missingTokens("edit auth.ts", "edit oauth.tsx")).toEqual(["auth.ts"]);
	});

	test("new tokens are those the input never had", () => {
		expect(newTokens("fix the login", "Fix login in auth.ts")).toEqual(["auth.ts"]);
	});
});

test("wordCount skips bare punctuation", () => {
	expect(wordCount("- one, two -- three")).toBe(3);
});

test("percentile by nearest rank", () => {
	expect(percentile([5, 1, 3, 2, 4], 50)).toBe(3);
	expect(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90)).toBe(9);
});

test("stratified takes an equal share from each length quartile, in set order", () => {
	const set = [8, 1, 7, 2, 6, 3, 5, 4].map((w) => ({ id: `p${w}`, inWords: w }));
	expect(stratified(set, 4).map((p) => p.id)).toEqual(["p1", "p3", "p6", "p8"]);
});
