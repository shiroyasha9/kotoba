// Scoring for kotoba-bench: normalized WER and technical-term recall.

const FILLERS = new Set(["um", "umm", "uh", "uhh", "uhm", "erm", "hmm", "hm"]);

// Quotes, brackets and sentence punctuation at the edges of a whitespace token.
const LEADING_PUNCT = /^["'“”‘’`(\[{<*]+/;
const TRAILING_PUNCT = /["'“”‘’`)\]}>*.,!?;:]+$/;

/** Strips edge punctuation but keeps case and inner characters. */
export function stripEdges(token: string): string {
	return token.replace(LEADING_PUNCT, "").replace(TRAILING_PUNCT, "");
}

/** A letter or digit, one of `chars`, then a letter or digit: `auth.ts`, `user_id`. */
const joinedBy = (chars: string) => new RegExp(`[\\p{L}\\p{N}][${chars}][\\p{L}\\p{N}]`, "u");
/** A CLI flag: `-v`, `--force`. */
const FLAG = /^-{1,2}\p{L}/u;
// WER keeps more shapes intact (`@scope`, `a\\b`, `.env`, `~/x`) than term recall counts as technical.
const IDENTIFIER_JOIN = joinedBy("._/:@\\\\-");
const TECHNICAL_JOIN = joinedBy("_./:-");

/** True for tokens such as `auth.ts`, `src/app`, `--force`, `.env`, `v2`, `user_id`, `localhost:3000`. */
function isIdentifierShaped(token: string): boolean {
	return IDENTIFIER_JOIN.test(token) || FLAG.test(token) || /^[.~/]\p{L}/u.test(token);
}

/**
 * Normalizes text for WER: lowercase, punctuation removed (letters, combining
 * marks such as Devanagari vowel signs, and digits stay) except inside
 * identifier-shaped tokens, whitespace collapsed, fillers dropped.
 */
export function normalize(text: string): string[] {
	const out: string[] = [];
	for (const raw of text.toLowerCase().split(/\s+/)) {
		let token = stripEdges(raw);
		if (!isIdentifierShaped(token)) token = token.replace(/[^\p{L}\p{M}\p{N}]+/gu, "");
		if (token && !FILLERS.has(token)) out.push(token);
	}
	return out;
}

export type AlignOp =
	| { op: "ok"; ref: string; hyp: string }
	| { op: "sub"; ref: string; hyp: string }
	| { op: "del"; ref: string }
	| { op: "ins"; hyp: string };

/** Token-level Levenshtein alignment (unit costs), with a backtrace. */
export function align(ref: string[], hyp: string[]): AlignOp[] {
	const rows = ref.length + 1;
	const cols = hyp.length + 1;
	const d = new Uint32Array(rows * cols);
	for (let i = 0; i < rows; i++) d[i * cols] = i;
	for (let j = 0; j < cols; j++) d[j] = j;
	for (let i = 1; i < rows; i++) {
		for (let j = 1; j < cols; j++) {
			const cost = ref[i - 1] === hyp[j - 1] ? 0 : 1;
			d[i * cols + j] = Math.min(
				d[(i - 1) * cols + j]! + 1,
				d[i * cols + j - 1]! + 1,
				d[(i - 1) * cols + j - 1]! + cost,
			);
		}
	}
	const ops: AlignOp[] = [];
	let i = ref.length;
	let j = hyp.length;
	while (i > 0 || j > 0) {
		const here = d[i * cols + j]!;
		if (i > 0 && j > 0) {
			const same = ref[i - 1] === hyp[j - 1];
			if (d[(i - 1) * cols + j - 1]! + (same ? 0 : 1) === here) {
				ops.push({ op: same ? "ok" : "sub", ref: ref[i - 1]!, hyp: hyp[j - 1]! });
				i--;
				j--;
				continue;
			}
		}
		if (i > 0 && d[(i - 1) * cols + j]! + 1 === here) {
			ops.push({ op: "del", ref: ref[i - 1]! });
			i--;
		} else {
			ops.push({ op: "ins", hyp: hyp[j - 1]! });
			j--;
		}
	}
	return ops.reverse();
}

export type WerCounts = { errors: number; refWords: number; ops: AlignOp[] };

/** Word errors (S + D + I) between two raw texts after normalization. */
export function wer(reference: string, hypothesis: string): WerCounts {
	const ref = normalize(reference);
	const ops = align(ref, normalize(hypothesis));
	return { errors: ops.filter((o) => o.op !== "ok").length, refWords: ref.length, ops };
}

/** Compact diff such as `the [off→of] -word +extra`, cut to `maxChars`. */
export function shortDiff(ops: AlignOp[], maxChars = 240): string {
	const parts: string[] = [];
	let okRun = 0;
	for (const o of ops) {
		if (o.op === "ok") {
			okRun++;
			continue;
		}
		if (okRun) parts.push(okRun > 2 ? "…" : "·".repeat(okRun));
		okRun = 0;
		if (o.op === "sub") parts.push(`[${o.ref}→${o.hyp}]`);
		else if (o.op === "del") parts.push(`-${o.ref}`);
		else parts.push(`+${o.hyp}`);
	}
	const text = parts.join(" ");
	return text.length > maxChars ? `${text.slice(0, maxChars - 1)}…` : text;
}

/**
 * Indexes of reference tokens that look technical: inner `_ . / - :`, camelCase,
 * letters mixed with digits, backticked, or part of a dictionary term.
 */
export function technicalTokens(rawTokens: string[], dictionaryTerms: string[]): Set<number> {
	const marked = new Set<number>();
	const bare = rawTokens.map(stripEdges);
	bare.forEach((t, i) => {
		if (!t) return;
		if (
			TECHNICAL_JOIN.test(t) ||
			FLAG.test(t) ||
			/\p{Ll}\p{Lu}/u.test(t) ||
			(/\p{L}/u.test(t) && /\p{N}/u.test(t)) ||
			rawTokens[i]!.includes("`")
		) {
			marked.add(i);
		}
	});
	const lower = bare.map((t) => t.toLowerCase());
	for (const term of dictionaryTerms) {
		const words = term.toLowerCase().split(/\s+/).map(stripEdges).filter(Boolean);
		if (!words.length) continue;
		for (let i = 0; i + words.length <= lower.length; i++) {
			if (words.every((w, k) => lower[i + k] === w)) {
				for (let k = 0; k < words.length; k++) marked.add(i + k);
			}
		}
	}
	return marked;
}

export type TermCounts = { hits: number; total: number; missed: string[] };

/** Share of technical reference tokens found exactly (case-sensitive, multiset) in the hypothesis. */
export function termRecall(reference: string, hypothesis: string, dictionaryTerms: string[]): TermCounts {
	const rawTokens = reference.split(/\s+/).filter(Boolean);
	const marked = technicalTokens(rawTokens, dictionaryTerms);
	const pool = new Map<string, number>();
	for (const t of hypothesis.split(/\s+/)) {
		const bare = stripEdges(t);
		if (bare) pool.set(bare, (pool.get(bare) ?? 0) + 1);
	}
	let hits = 0;
	const missed: string[] = [];
	for (const i of [...marked].sort((a, b) => a - b)) {
		const token = stripEdges(rawTokens[i]!);
		const left = pool.get(token) ?? 0;
		if (left > 0) {
			hits++;
			pool.set(token, left - 1);
		} else {
			missed.push(token);
		}
	}
	return { hits, total: marked.size, missed };
}
