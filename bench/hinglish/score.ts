// Scoring for the synthetic Hinglish bench: script shares, a Hinglish
// spelling fold, and an approximate ICU transliteration of Devanagari words.

import { join } from "node:path";
import { $ } from "bun";
import { align, stripEdges } from "../score.ts";

// --- Script check -------------------------------------------------------

export type ScriptShare = { latin: number; devanagari: number; other: number; letters: number };

/** Shares of letters (not marks or digits) by script; all zero for a text without letters. */
export function scriptShare(text: string): ScriptShare {
	let latin = 0;
	let devanagari = 0;
	let other = 0;
	for (const ch of text.normalize("NFC")) {
		if (!/\p{L}/u.test(ch)) continue;
		if (/\p{Script=Latin}/u.test(ch)) latin++;
		else if (/\p{Script=Devanagari}/u.test(ch)) devanagari++;
		else other++;
	}
	const letters = latin + devanagari + other;
	const share = (n: number) => (letters ? n / letters : 0);
	return { latin: share(latin), devanagari: share(devanagari), other: share(other), letters };
}

export const hasDevanagari = (text: string) => /\p{Script=Devanagari}/u.test(text);

// --- Tokens and folds ---------------------------------------------------

const FILLERS = new Set(["um", "umm", "uh", "uhh", "uhm", "erm", "hmm", "hm"]);

const NUKTA = /़/g;
const CANDRABINDU = /ँ/g;
const ANUSVARA = "ं";

/** Common spelling variants, keyed by their form after the character folds in `foldLatin`. */
const LATIN_WORDS: Record<string, string> = {
	nahin: "nahi",
	nhi: "nahi",
	kia: "kya",
	men: "mein",
	hu: "hun",
	kyu: "kyun",
	kyon: "kyun",
	kyonki: "kyunki",
	yeh: "ye",
	voh: "vo",
	toh: "to",
	ham: "hum",
	pahle: "pehle",
	tumhen: "tumhe",
	tumhein: "tumhe",
};

/**
 * One spelling per Hinglish word, applied to reference and output alike:
 * no diacritics, ee -> i, oo -> u, z -> j, ph -> f, q -> k, w -> v, runs of
 * one letter collapsed (accha, chhote), y between vowels dropped (gayi,
 * chahiye), then LATIN_WORDS.
 */
export function foldLatin(token: string): string {
	const t = token
		.normalize("NFD")
		.replace(/\p{M}/gu, "")
		.replace(/ee/g, "i")
		.replace(/oo/g, "u")
		.replace(/z/g, "j")
		.replace(/ph/g, "f")
		.replace(/q/g, "k")
		.replace(/w/g, "v")
		.replace(/(\p{L})\1+/gu, "$1")
		.replace(/([aeiou])y(?=[aeiou])/g, "$1");
	return LATIN_WORDS[t] ?? t;
}

/** Devanagari spelling variants: nukta dropped, candrabindu written as anusvara. */
export function foldDevanagari(token: string): string {
	return token.normalize("NFD").replace(NUKTA, "").replace(CANDRABINDU, ANUSVARA).normalize("NFC");
}

/** Lowercase words without punctuation or fillers; `fold` adds the spelling folds. */
export function tokens(text: string, fold = true): string[] {
	const out: string[] = [];
	for (const raw of text.normalize("NFC").toLowerCase().split(/\s+/)) {
		const bare = stripEdges(raw).replace(/[^\p{L}\p{M}\p{N}]+/gu, "");
		if (!bare || FILLERS.has(bare)) continue;
		if (!fold) out.push(bare);
		else out.push(hasDevanagari(bare) ? foldDevanagari(bare) : foldLatin(bare));
	}
	return out;
}

// --- Transliteration (approximate) -------------------------------------

const isConsonant = (c: number) => c >= 0x915 && c <= 0x939;
const isMatra = (c: number) => (c >= 0x93e && c <= 0x94c) || c === 0x962 || c === 0x963;
const VIRAMA = 0x94d;

/**
 * Hindi schwa deletion, simplified: a consonant with its inherent "a" loses
 * it at the end of a word (कर -> kar, और -> aur) and before a consonant
 * with a vowel sign (करना -> karnā), but never as the first letter.
 * Inserts a virama there.
 */
export function deleteSchwa(word: string): string {
	const chars = [...foldDevanagari(word)].map((c) => c.codePointAt(0)!);
	const units: { at: number; inherent: boolean; matra: boolean }[] = [];
	chars.forEach((c, i) => {
		if (!isConsonant(c)) return;
		const next = chars[i + 1];
		const matra = next !== undefined && isMatra(next);
		units.push({ at: i, inherent: !matra && next !== VIRAMA, matra });
	});
	const drop = new Set<number>();
	const last = units.at(-1);
	if (last?.inherent && last.at > 0 && last.at === chars.length - 1) drop.add(last.at);
	for (let u = 0; u < units.length - 1; u++) {
		const here = units[u]!;
		if (here.at > 0 && here.inherent && units[u + 1]!.matra && chars[here.at + 1] !== 0x902) drop.add(here.at);
	}
	return chars.map((c, i) => String.fromCodePoint(c) + (drop.has(i) ? String.fromCodePoint(VIRAMA) : "")).join("");
}

/** ICU Latin to casual Hinglish: anusvara and candrabindu -> n, ś ṣ -> sh, c -> ch, ch (छ) -> chh, no diacritics. */
export function casualLatin(icu: string): string {
	return icu
		.normalize("NFC")
		.replace(/ṁ|ṃ|m̐/g, "n")
		.replace(/[śṣ]/g, "sh")
		.replace(/r̥/g, "ri")
		.replace(/ch/g, "\u0001")
		.replace(/c/g, "ch")
		.replace(/\u0001/g, "chh")
		.normalize("NFD")
		.replace(/\p{M}/gu, "")
		.toLowerCase();
}

const TRANSLIT_SWIFT = join(import.meta.dir, "translit.swift");

/** Runs ICU Devanagari-Latin (Foundation's StringTransform) on each word in one swift process. */
export async function icuLatin(words: string[]): Promise<Map<string, string>> {
	const unique = [...new Set(words)];
	if (!unique.length) return new Map();
	const input = new Response(`${unique.join("\n")}\n`);
	const out = (await $`swift ${TRANSLIT_SWIFT} < ${input}`.text()).split("\n");
	return new Map(unique.map((w, i) => [w, out[i] ?? w]));
}

/** Builds a word -> casual Latin table for every Devanagari word in `texts`, the keys `romanize` looks up. */
export async function translitTable(texts: string[]): Promise<Map<string, string>> {
	const words = texts.flatMap((t) => tokens(t, false).filter(hasDevanagari));
	const icu = await icuLatin(words.map(deleteSchwa));
	return new Map(words.map((w) => [w, casualLatin(icu.get(deleteSchwa(w)) ?? w)]));
}

/** Text with each Devanagari word replaced from `table`; Latin words stay. Approximate. */
export function romanize(text: string, table: Map<string, string>): string {
	return tokens(text, false)
		.map((w) => (hasDevanagari(w) ? (table.get(w) ?? w) : w))
		.join(" ");
}

// --- WER ----------------------------------------------------------------

export type Wer = { errors: number; refWords: number };

export function werTokens(ref: string[], hyp: string[]): Wer {
	return { errors: align(ref, hyp).filter((o) => o.op !== "ok").length, refWords: ref.length };
}

/** WER in the reference's own script, with folds: Devanagari words in Hinglish output count as errors. */
export const werDirect = (reference: string, hypothesis: string): Wer =>
	werTokens(tokens(reference), tokens(hypothesis));

/** Script-blind WER: both sides romanized with `table` first. Approximate (ICU plus simple rules). */
export const werRomanized = (reference: string, hypothesis: string, table: Map<string, string>): Wer =>
	werTokens(tokens(romanize(reference, table)), tokens(romanize(hypothesis, table)));

/** Corpus WER: all errors over all reference words; null without reference words. */
export function corpusRate(ws: Wer[]): number | null {
	const refWords = ws.reduce((s, w) => s + w.refWords, 0);
	return refWords ? ws.reduce((s, w) => s + w.errors, 0) / refWords : null;
}
