// OpenRouter HTTP plumbing shared by the STT and cleanup passes: raw JSONL
// logging, the cost cap, a bounded worker pool and retry with backoff.

import { appendFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";

export const API = "https://openrouter.ai/api/v1";

// --- JSONL --------------------------------------------------------------

const appendChains = new Map<string, Promise<void>>();

/** Appends one JSON line per row in one write; appends to the same file are serialized, and its folder is made on the first append. */
export function appendJsonl(path: string, ...rows: unknown[]): Promise<void> {
	const lines = rows.map((row) => `${JSON.stringify(row)}\n`).join("");
	const prev = appendChains.get(path) ?? mkdir(dirname(path), { recursive: true }).then(() => {});
	const next = prev.then(() => appendFile(path, lines));
	appendChains.set(path, next);
	return next;
}

/** Reads a JSONL file; a missing file is empty, and a torn last line (crash mid-write) is skipped. */
export async function readJsonl<T>(path: string): Promise<T[]> {
	const file = Bun.file(path);
	if (!(await file.exists())) return [];
	const rows: T[] = [];
	// Parsed line by line, not with Bun.JSONL: a crash can leave a partial last line, and that must not lose the file.
	const lines = (await file.text()).split("\n");
	lines.forEach((line, i) => {
		if (!line.trim()) return;
		try {
			rows.push(JSON.parse(line));
		} catch {
			console.warn(`${path}:${i + 1}: skipping unparsable line`);
		}
	});
	return rows;
}

export type RawRow = { variant: string; clipId: string; ok: boolean; text: string | null; cost: number | null };

/** First successful row per (variant, clip). */
export function okRowsByVariant<R extends RawRow>(rows: R[]): Map<string, Map<string, R>> {
	const out = new Map<string, Map<string, R>>();
	for (const r of rows) {
		if (!r.ok || r.text == null) continue;
		const byClip = out.get(r.variant) ?? new Map<string, R>();
		if (!byClip.has(r.clipId)) byClip.set(r.clipId, r);
		out.set(r.variant, byClip);
	}
	return out;
}

// --- Cost cap -----------------------------------------------------------

export const sumCost = (rows: { cost: number | null }[]) => rows.reduce((s, r) => s + (r.cost ?? 0), 0);

/** Total `usage.cost` recorded in the given raw files. */
export async function spentUsd(rawFiles: string[]): Promise<number> {
	const totals = await Promise.all(rawFiles.map(async (f) => sumCost(await readJsonl<{ cost: number | null }>(f))));
	return totals.reduce((a, b) => a + b, 0);
}

/** Running total of `usage.cost`, seeded from the raw files so the cap spans resumed runs. */
export class Budget {
	total: number;
	exceeded = false;

	constructor(
		readonly cap: number,
		seed: number,
	) {
		this.total = seed;
		this.exceeded = seed > cap;
	}

	add(cost: number | null | undefined): void {
		if (typeof cost === "number" && Number.isFinite(cost)) this.total += cost;
		if (this.total > this.cap && !this.exceeded) {
			this.exceeded = true;
			console.error(`cost cap hit: $${this.total.toFixed(4)} > $${this.cap}; no new requests will start`);
		}
	}
}

// --- Pool and retry -----------------------------------------------------

/** Runs `worker` over `items` with at most `concurrency` in flight; stops starting new items once `stop()` is true. */
export async function runPool<T>(
	items: T[],
	concurrency: number,
	worker: (item: T) => Promise<void>,
	stop: () => boolean,
): Promise<number> {
	let next = 0;
	let started = 0;
	const lane = async () => {
		while (next < items.length && !stop()) {
			const item = items[next++]!;
			started++;
			await worker(item);
		}
	};
	await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, lane));
	return started;
}

export type Attempt = { status: number; retryAfterSec?: number | null };

const retryable = (status: number) => status === 0 || status === 408 || status === 429 || status >= 500;

/** Calls `attempt(n)` until it returns a non-retryable status or `maxAttempts` is reached. Backoff 1, 2, 4, 8, 16 s plus jitter, or Retry-After. */
export async function withRetry<T extends Attempt>(attempt: (n: number) => Promise<T>, maxAttempts = 6): Promise<T> {
	for (let n = 1; ; n++) {
		const result = await attempt(n);
		if (!retryable(result.status) || n >= maxAttempts) return result;
		const backoff = result.retryAfterSec ? result.retryAfterSec * 1000 : 1000 * 2 ** (n - 1);
		await Bun.sleep(backoff + Math.random() * 500);
	}
}

export type LoggedRow = { status: number; ok: boolean; cost: number | null; error?: string };

/** Where a paid call writes its rows and books its cost. */
export type CallSink = { out: string; budget: Budget };

/**
 * One paid call with retries: every attempt's row is appended to `sink.out`
 * as it completes and its cost added to the budget. `retryAfterSec` steers
 * the backoff and is not written.
 */
export function loggedCall<R extends LoggedRow>(
	sink: CallSink,
	attempt: (n: number) => Promise<{ row: R; retryAfterSec: number | null }>,
): Promise<R> {
	return withRetry(async (n) => {
		const { row, retryAfterSec } = await attempt(n);
		await appendJsonl(sink.out, row);
		sink.budget.add(row.cost);
		return { ...row, retryAfterSec };
	});
}

/** Runs paid calls through the pool with progress lines; stops starting calls once the budget is spent. */
export async function runCalls<T>(
	label: string,
	items: T[],
	concurrency: number,
	budget: Budget,
	call: (item: T) => Promise<LoggedRow>,
	describe: (item: T) => string,
): Promise<void> {
	let finished = 0;
	await runPool(
		items,
		concurrency,
		async (item) => {
			const row = await call(item);
			finished++;
			if (!row.ok) console.warn(`  ${label} ${describe(item)}: ${row.status} ${row.error?.slice(0, 120) ?? ""}`);
			if (finished % 25 === 0) console.log(`  ${label} ${finished}/${items.length}  $${budget.total.toFixed(4)}`);
		},
		() => budget.exceeded,
	);
}

export function retryAfter(res: Response): number | null {
	const v = Number(res.headers.get("retry-after"));
	return Number.isFinite(v) && v > 0 ? v : null;
}

export function authHeaders(): Record<string, string> {
	const key = Bun.env.OPENROUTER_API_KEY;
	if (!key) throw new Error("OPENROUTER_API_KEY not set (run with bun --env-file=...)");
	return { Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
}

// --- Model checks (free GETs) ------------------------------------------

/** Fails unless every id is listed by the free models endpoints and each pinned provider tag serves its model. */
export async function confirmModels(
	sttIds: string[],
	chatIds: string[],
	pinned: { model: string; provider: string }[],
): Promise<void> {
	const list = async (url: string) =>
		new Set(((await (await fetch(url)).json()) as { data: { id: string }[] }).data.map((m) => m.id));
	const serves = async ({ model, provider }: { model: string; provider: string }) => {
		const eps = (await (await fetch(`${API}/models/${model}/endpoints`)).json()) as {
			data: { endpoints: { tag: string }[] };
		};
		return eps.data.endpoints.some((e) => e.tag === provider || e.tag.startsWith(`${provider}/`));
	};
	const [stt, chat, pinOk] = await Promise.all([
		list(`${API}/models?output_modalities=transcription`),
		list(`${API}/models`),
		Promise.all(pinned.map(serves)),
	]);
	const missing = [
		...sttIds.filter((id) => !stt.has(id)),
		...chatIds.filter((id) => !chat.has(id)),
		...pinned.filter((_, i) => !pinOk[i]).map(({ model, provider }) => `${model} via ${provider}`),
	];
	if (missing.length) throw new Error(`models not available on OpenRouter: ${missing.join(", ")}`);
}
