// Local page for hand-correcting reference transcripts.
// Usage: bun run review [--data DIR] [--port N]   (DIR defaults to $KOTOBA_BENCH_DATA)

import { join } from "node:path";
import { parseArgs } from "node:util";
import { fail, intArg } from "../cli.ts";
import { BENCH_SEED, type ManifestRow, paths, pickReference } from "../data.ts";
import { type RawRow, appendJsonl, readJsonl } from "../openrouter.ts";
import page from "./index.html";
import { type Candidate, candidates, selectClips } from "./select.ts";

export type ReferenceRow = { clipId: string; text: string; source: "owner" | "edited"; savedAt: string };

/** The fixed review set, written once so later STT runs cannot reshuffle it mid-review. */
type ReviewSet = { seed: number; createdAt: string; clipIds: string[] };

const { values: args } = parseArgs({
	args: Bun.argv.slice(2),
	options: {
		data: { type: "string", default: Bun.env.KOTOBA_BENCH_DATA },
		port: { type: "string", default: "4788" },
	},
});
if (!args.data) fail("set KOTOBA_BENCH_DATA or pass --data DIR");
const port = intArg(args, "port", 1)!;
const p = paths(args.data);

const setFile = Bun.file(p.reviewSet);
const [manifest, stt, refRows, set] = await Promise.all([
	Bun.file(p.manifest).json() as Promise<ManifestRow[]>,
	readJsonl<RawRow>(p.sttRaw),
	readJsonl<ReferenceRow>(p.references),
	setFile.exists().then((ok) => (ok ? (setFile.json() as Promise<ReviewSet>) : null)),
]);
/** Last write per clip wins; /api/save keeps it current. */
const refs = new Map(refRows.map((r) => [r.clipId, r]));

let review: Candidate[];
if (set) {
	const ids = new Set(set.clipIds);
	const byId = new Map(candidates(manifest.filter((r) => ids.has(r.transcriptEntityId)), stt).map((c) => [c.id, c]));
	review = set.clipIds.map((id) => byId.get(id)).filter((c): c is Candidate => c != null);
	if (review.length !== set.clipIds.length) {
		console.warn(`review-set.json: ${set.clipIds.length - review.length} clips no longer have STT text`);
	}
} else {
	review = selectClips(candidates(manifest, stt));
	const fresh: ReviewSet = { seed: BENCH_SEED, createdAt: new Date().toISOString(), clipIds: review.map((c) => c.id) };
	await Bun.write(p.reviewSet, `${JSON.stringify(fresh, null, "\t")}\n`);
}

// The owner's earlier Wispr edits are references already; copy them in once.
const edited = manifest.flatMap((row): ReferenceRow[] => {
	const ref = pickReference(row);
	if (ref?.refSource !== "edited" || refs.has(row.transcriptEntityId)) return [];
	return [{ clipId: row.transcriptEntityId, text: ref.reference, source: "edited", savedAt: new Date().toISOString() }];
});
if (edited.length) await appendJsonl(p.references, ...edited);
for (const r of edited) refs.set(r.clipId, r);

const reviewIds = new Set(review.map((c) => c.id));
const notFound = () => new Response("not found", { status: 404 });

const server = Bun.serve({
	hostname: "127.0.0.1",
	port,
	routes: {
		"/": page,
		"/api/session": () => {
			const saved = Object.fromEntries(
				review.flatMap((c) => {
					const r = refs.get(c.id);
					return r?.source === "owner" ? [[c.id, r.text]] : [];
				}),
			);
			return Response.json({ clips: review, saved });
		},
		"/api/save": {
			POST: async (req) => {
				const body = (await req.json().catch(() => null)) as { clipId?: unknown; text?: unknown } | null;
				const text = typeof body?.text === "string" ? body.text.trim() : "";
				if (typeof body?.clipId !== "string" || !reviewIds.has(body.clipId) || !text) {
					return Response.json({ error: "clipId from the review set and non-empty text are required" }, { status: 400 });
				}
				const row: ReferenceRow = { clipId: body.clipId, text, source: "owner", savedAt: new Date().toISOString() };
				await appendJsonl(p.references, row);
				refs.set(row.clipId, row);
				return Response.json(row);
			},
		},
		// Bun answers Range requests for a file body, so the audio element can seek.
		"/audio/:id": async (req) => {
			const id = req.params.id.replace(/\.wav$/, "");
			const wav = Bun.file(join(p.clips, `${id}.wav`));
			if (!reviewIds.has(id) || !(await wav.exists())) return notFound();
			return new Response(wav, { headers: { "Cache-Control": "private, max-age=86400" } });
		},
	},
	fetch: notFound,
});

console.log(`${review.length} clips to review, ${edited.length} edited references copied to ${p.references}`);
console.log(`Open ${server.url}`);
