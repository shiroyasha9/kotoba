// Code-side Polish checks: exact survival of code-like tokens, new tokens, word ratio, and characters that break a
// terminal prompt. The LLM judge (judge.ts) checks instructions and facts.

/** Wispr stores lists as <ul>/<ol>/<li> HTML; kotoba's input is plain text, so lists become "- " and "1. " lines. */
export function htmlToText(html: string): string {
	let n = 0;
	let ordered = false;
	return html
		.replace(/<(ul|ol)[^>]*>|<\/(ul|ol)>|<li[^>]*>|<\/li>|<br\s*\/?>|<\/?p>/gi, (tag) => {
			const t = tag.toLowerCase();
			if (t.startsWith("<ol")) {
				ordered = true;
				n = 0;
				return "\n";
			}
			if (t.startsWith("<ul")) {
				ordered = false;
				return "\n";
			}
			if (t.startsWith("<li")) return ordered ? `\n${++n}. ` : "\n- ";
			if (t === "</li>") return "";
			return "\n";
		})
		.replace(/[ \t]+\n/g, "\n")
		.replace(/\n{3,}/g, "\n\n")
		.trim();
}

/** Non-ASCII hyphens and spaces (U+2010-2011, U+00A0, U+202F) and curly quotes become their ASCII forms. */
export const normalize = (s: string) =>
	s
		.replace(/[\u2010\u2011]/g, "-")
		.replace(/[\u00a0\u202f]/g, " ")
		.replace(/[\u2018\u2019]/g, "'")
		.replace(/[\u201c\u201d]/g, '"');

export const wordCount = (s: string) => s.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;

/** Characters a terminal prompt should not get: a non-ASCII hyphen or space inside the text. */
export const badChars = (s: string) => (s.match(/[\u2010\u2011\u00a0\u202f]/g) ?? []).length;

/**
 * Code-like tokens: paths, file names, dotted or snake_case identifiers, slash commands, flags, URLs, camelCase and
 * PascalCase with an inner capital, all-caps words of 2+ letters, numbers, and backticked spans. Hyphenated words
 * ("re-ranking") and Latin abbreviations ("e.g") are prose, not tokens.
 */
export function codeTokens(text: string): string[] {
	const s = normalize(text);
	const out = new Set<string>();
	for (const m of s.matchAll(/`([^`\n]{1,80})`/g)) out.add(m[1]!.trim());
	for (const raw of s.split(/[\s,;()[\]{}"<>]+/)) {
		// Trailing sentence punctuation is not part of the token; a leading "/" or "-" is.
		const w = raw.replace(/[.:!?'*]+$/, "").replace(/^['*]+/, "");
		if (w.length < 2 || /^(e\.g|i\.e|etc)$/i.test(w)) continue;
		if (
			/^https?:\/\//.test(w) ||
			/^--?[a-z]/i.test(w) ||
			/^\/[a-z]/i.test(w) ||
			/[a-z0-9][./_:@#][a-z0-9]/i.test(w) ||
			/[a-z][A-Z]/.test(w) ||
			/^[A-Z]{2,}[a-z]?$/.test(w) ||
			/\d/.test(w)
		)
			out.add(w);
	}
	return [...out];
}

/** Tokens of `input` that do not occur in `output` (case-sensitive, after `normalize`, bounded by non-word chars). */
export function missingTokens(input: string, output: string): string[] {
	const o = normalize(output);
	return codeTokens(input).filter((t) => !containsToken(o, t));
}

/** Code-like tokens of `output` that occur nowhere in `input` (case-insensitive): invented identifiers or numbers. */
export function newTokens(input: string, output: string): string[] {
	const i = normalize(input).toLowerCase();
	return codeTokens(output).filter((t) => !containsToken(i, t.toLowerCase()));
}

function containsToken(haystack: string, token: string): boolean {
	const escapedToken = token.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
	return new RegExp(`(^|[^\\p{L}\\p{N}_])${escapedToken}($|[^\\p{L}\\p{N}_])`, "u").test(haystack);
}

/** p-th percentile (0-100) by nearest rank; NaN when empty. */
export function percentile(values: number[], p: number): number {
	if (!values.length) return Number.NaN;
	const sorted = [...values].sort((a, b) => a - b);
	return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1))]!;
}

/** `n` inputs of `set`, an equal share from each input-length quartile, in hash order within each quartile. */
export function stratified<T extends { id: string; inWords: number }>(set: T[], n: number): T[] {
	const byLength = [...set].sort((a, b) => a.inWords - b.inWords);
	const q = Math.ceil(byLength.length / 4);
	const quartiles = [0, 1, 2, 3].map((i) => new Set(byLength.slice(i * q, (i + 1) * q).map((p) => p.id)));
	return quartiles.flatMap((ids, i) => set.filter((p) => ids.has(p.id)).slice(0, Math.floor(n / 4) + (i < n % 4 ? 1 : 0)));
}

/** Deterministic split: the first `dev` items of a seeded shuffle are the dev set (prompt choice), the rest the test set. */
export function split<T extends { id: string }>(items: T[], dev: number): { dev: T[]; test: T[] } {
	const keyed = items.map((x) => ({ x, k: hash(x.id) })).sort((a, b) => a.k - b.k);
	return { dev: keyed.slice(0, dev).map((e) => e.x), test: keyed.slice(dev).map((e) => e.x) };
}

/** FNV-1a 32-bit. */
function hash(s: string): number {
	let h = 0x811c9dc5;
	for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 0x01000193) >>> 0;
	return h;
}
