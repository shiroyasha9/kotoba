// Local page for hand-correcting reference transcripts.
// Usage: bun run review [--data DIR] [--port N]   (DIR defaults to $KOTOBA_BENCH_DATA)

import { join } from "node:path";
import { parseArgs } from "node:util";
import { fail, intArg } from "../cli.ts";
import { BENCH_SEED, type ManifestRow, type ReferenceRow, loadReferences, paths, pickReference } from "../data.ts";
import { type RawRow, appendJsonl, readJsonl } from "../openrouter.ts";
import page from "./index.html";
import { type Candidate, candidates, reviewOrder, selectClips } from "./select.ts";

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
const [manifest, stt, refs, set] = await Promise.all([
	Bun.file(p.manifest).json() as Promise<ManifestRow[]>,
	readJsonl<RawRow>(p.sttRaw),
	/** Last write per clip wins; /api/save keeps it current. */
	loadReferences(p),
	setFile.exists().then((ok) => (ok ? (setFile.json() as Promise<ReviewSet>) : null)),
]);

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
// The page shows the set shortest first; review-set.json keeps the chosen set, not this order.
review = reviewOrder(review);

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

const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);

/**
 * Blocks DNS rebinding (a foreign Host) and cross-site requests (a foreign Origin)
 * before a handler reads clips or writes references. A POST must be JSON, so a
 * cross-site form or no-cors fetch cannot send it without a CORS preflight.
 */
function guard(req: Request): Response | null {
	const host = req.headers.get("host") ?? "";
	if (!allowedHosts.has(host)) return new Response("forbidden host", { status: 403 });
	const origin = req.headers.get("origin");
	if (origin !== null && origin !== `http://${host}`) return new Response("forbidden origin", { status: 403 });
	const mediaType = req.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase();
	if (req.method === "POST" && mediaType !== "application/json") {
		return new Response("POST needs Content-Type: application/json", { status: 415 });
	}
	return null;
}

const guarded =
	<R extends Request>(handler: (req: R) => Response | Promise<Response>) =>
	(req: R) =>
		guard(req) ?? handler(req);

const server = Bun.serve({
	hostname: "127.0.0.1",
	port,
	routes: {
		"/": page,
		// The HTML import and its bundle are served by Bun without a handler; they hold no clip data.
		"/api/session": guarded(() => {
			const saved = Object.fromEntries(
				review.flatMap((c) => {
					const r = refs.get(c.id);
					return r?.source === "owner" ? [[c.id, r.text]] : [];
				}),
			);
			return Response.json({ clips: review, saved });
		}),
		"/api/save": {
			POST: guarded(async (req) => {
				const body = (await req.json().catch(() => null)) as { clipId?: unknown; text?: unknown } | null;
				const text = typeof body?.text === "string" ? body.text.trim() : "";
				if (typeof body?.clipId !== "string" || !reviewIds.has(body.clipId) || !text) {
					return Response.json({ error: "clipId from the review set and non-empty text are required" }, { status: 400 });
				}
				const row: ReferenceRow = { clipId: body.clipId, text, source: "owner", savedAt: new Date().toISOString() };
				await appendJsonl(p.references, row);
				refs.set(row.clipId, row);
				return Response.json(row);
			}),
		},
		// Bun answers Range requests for a file body, so the audio element can seek.
		"/audio/:id": guarded(async (req) => {
			const id = req.params.id.replace(/\.wav$/, "");
			const wav = Bun.file(join(p.clips, `${id}.wav`));
			if (!reviewIds.has(id) || !(await wav.exists())) return notFound();
			return new Response(wav, { headers: { "Cache-Control": "private, max-age=86400" } });
		}),
	},
	fetch: guarded(notFound),
});

console.log(`${review.length} clips to review, ${edited.length} edited references copied to ${p.references}`);
console.log(`Open ${server.url}`);
