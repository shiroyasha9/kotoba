import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import {
	CLEANUP_MODELS,
	PROMPTS,
	PROMPT_VERSIONS,
	requestBody,
	isWritingVariant,
	systemPrompt,
	variantKey,
	writingClips,
	writingSystemPrompt,
} from "./cleanup.ts";
import type { Clip } from "./data.ts";

const fixtures = join(import.meta.dir, "../KotobaProviders/Tests/KotobaProvidersTests/Fixtures");
const vocabulary = ["kotoba", "DictationPipeline"];

describe("prompts", () => {
	// kotoba's OpenRouterCleaner copies both prompts word for word; its tests compare it with the same fixtures, so a
	// change on either side fails one of the two.
	test("the Code prompt is the fixture kotoba's cleaner matches", async () => {
		expect(systemPrompt(vocabulary)).toBe(await Bun.file(join(fixtures, "cleanup-system-prompt.txt")).text());
	});

	test("the Writing prompt is the fixture kotoba's cleaner matches", async () => {
		expect(writingSystemPrompt(vocabulary)).toBe(
			await Bun.file(join(fixtures, "cleanup-writing-system-prompt.txt")).text(),
		);
	});
});

describe("writing run", () => {
	const clip = (id: string, app: string | null, reference = "some words"): Clip =>
		({ id, app, reference }) as unknown as Clip;

	test("takes only clips dictated into the standard Writing apps (chat, mail, notes)", () => {
		const clips = [
			clip("slack", "com.tinyspeck.slackmacgap"),
			clip("notes", "com.apple.Notes"),
			clip("browser", "company.thebrowser.dia"),
			clip("terminal", "com.mitchellh.ghostty"),
			clip("editor", "com.todesktop.230313mzl4w4u92"),
			clip("unknown", null),
			clip("empty", "com.apple.Notes", " "),
		];

		expect(writingClips(clips).map((c) => c.id)).toEqual(["slack", "notes"]);
	});

	test("a Writing row has its own variant, so it never counts as a Code row", () => {
		expect(variantKey("gemini-3.5-flash-lite", "code")).toBe("gemini-3.5-flash-lite+code-v3");
		expect(variantKey("gemini-3.5-flash-lite", "writing")).toBe("gemini-3.5-flash-lite+writing-v3");
		expect(variantKey("gemini-3.5-flash-lite", "writing", 2, "task-last+t1")).toBe("gemini-3.5-flash-lite+writing-v2+task-last+t1");
	});

	test("Writing rows of every prompt version count as Writing rows, Code rows do not", () => {
		const writing = ["gemini-3.5-flash-lite+writing", "gemini-3.5-flash-lite+writing-v2", "gemini-3.5-flash-lite+writing-v2+t1"];
		expect(writing.every(isWritingVariant)).toBe(true);
		expect(["gemini-3.5-flash-lite", "gemini-3.5-flash-lite+code-v2"].some(isWritingVariant)).toBe(false);
	});

	test("a prompt change raises its PROMPT_VERSIONS entry", () => {
		// Update a version and its hash together: a new prompt under an old version would resume onto that version's rows.
		const hash = (s: string) => Bun.hash(s).toString(16);
		expect(PROMPT_VERSIONS).toEqual({ code: 3, writing: 3 });
		expect(hash(PROMPTS.code[2]!(vocabulary))).toBe("ac6d9fcb0fdada32");
		expect(hash(PROMPTS.writing[2]!(vocabulary))).toBe("504bdc7ec6524cca");
		expect(hash(PROMPTS.code[3]!(vocabulary))).toBe("2a22c07ac84a1e07");
		expect(hash(PROMPTS.writing[3]!(vocabulary))).toBe("7993c80e3a8af612");
	});

	test("the v3 prompts leave out an empty vocabulary block", () => {
		expect(PROMPTS.writing[3]!([])).not.toContain("<vocabulary>");
		expect(PROMPTS.code[3]!(vocabulary)).toEndWith("these terms: kotoba, DictationPipeline\n</vocabulary>");
	});

	test("from version 3, Gemini gets no temperature; a lever adds its sentence after the transcript", () => {
		const gemini = CLEANUP_MODELS.find((m) => m.key === "gemini-3.5-flash-lite")!;
		const job = { m: gemini, variant: "v", sttVariant: "s", clipId: "c", transcript: "hi", system: "sys" };
		expect(requestBody({ ...job, version: 2 }).temperature).toBe(0);
		expect(requestBody({ ...job, version: 3 })).not.toHaveProperty("temperature");
		const messages = requestBody({ ...job, version: 3, lever: "tail" }).messages as { content: string }[];
		expect(messages[1]!.content).toBe("<transcript>\nhi\n</transcript>\n\nReply with the transcript above, cleaned, with every sentence in it.");
	});
});
