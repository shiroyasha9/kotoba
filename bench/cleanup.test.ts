import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { systemPrompt, variantKey, writingClips, writingSystemPrompt } from "./cleanup.ts";
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
		expect(variantKey("gemini-3.5-flash-lite", "code")).toBe("gemini-3.5-flash-lite");
		expect(variantKey("gemini-3.5-flash-lite", "writing")).toBe("gemini-3.5-flash-lite+writing");
	});
});
