import { describe, expect, test } from "bun:test";
import { type ManifestRow, applyDictionary, durationBucket, mulberry32, pickReference, seededSample, shuffle } from "./data.ts";

const row = (texts: Partial<ManifestRow>): ManifestRow => ({
	transcriptEntityId: "x",
	timestamp: null,
	app: null,
	url: null,
	duration: null,
	numWords: null,
	e2eLatency: null,
	clientNetworkLatency: null,
	asrText: null,
	formattedText: null,
	editedText: null,
	pastedText: null,
	...texts,
});

describe("pickReference", () => {
	test("edited text wins when it differs from the formatted text", () => {
		expect(pickReference(row({ formattedText: "a", editedText: "b", pastedText: "a" }))).toEqual({
			reference: "b",
			refSource: "edited",
			refField: "editedText",
		});
	});

	test("unchanged edited text falls back to pasted, then formatted", () => {
		expect(pickReference(row({ formattedText: "a", editedText: "a", pastedText: "p" }))?.refField).toBe("pastedText");
		expect(pickReference(row({ formattedText: "a" }))?.refField).toBe("formattedText");
		expect(pickReference(row({}))).toBeNull();
	});
});

describe("applyDictionary", () => {
	const dict = [
		{ phrase: "open router", replacement: "OpenRouter" },
		{ phrase: "kotoba", replacement: "Kotoba" },
		{ phrase: "vocab only", replacement: null },
	];

	test("replaces whole words case-insensitively", () => {
		expect(applyDictionary("Call Open Router from kotoba.", dict)).toBe("Call OpenRouter from Kotoba.");
	});

	test("leaves partial-word matches alone", () => {
		expect(applyDictionary("kotobas and mykotoba", dict)).toBe("kotobas and mykotoba");
	});
});

test("durationBucket edges", () => {
	expect([9.9, 10, 19.9, 20, 40, 40.1].map(durationBucket)).toEqual([
		"<10 s",
		"10-20 s",
		"10-20 s",
		"20-40 s",
		"20-40 s",
		">40 s",
	]);
});

// Pinned outputs: the cleanup and latency samples, and the review set, must not move when this code changes.
test("seededSample and shuffle are pinned for a seed", () => {
	expect(seededSample(Array.from({ length: 20 }, (_, i) => i), 8)).toEqual([16, 12, 10, 1, 13, 5, 15, 7]);
	expect(shuffle([1, 2, 3, 4, 5, 6], mulberry32(1))).toEqual([5, 2, 6, 3, 1, 4]);
});
