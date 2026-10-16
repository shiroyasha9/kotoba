import { expect, test } from "bun:test";
import { join } from "node:path";
import { POLISH_PROMPTS } from "./prompts.ts";

const fixtures = join(import.meta.dir, "../../KotobaProviders/Tests/KotobaProvidersTests/Fixtures");

// kotoba's OpenRouterPolisher copies prompt v2 word for word; its tests compare it with the same fixture, so a change
// on either side fails one of the two.
test("prompt v2 is the fixture kotoba's polisher matches", async () => {
	expect(POLISH_PROMPTS[2]).toBe(await Bun.file(join(fixtures, "polish-system-prompt.txt")).text());
});
