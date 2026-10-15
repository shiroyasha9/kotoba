/// <reference lib="dom" />
// Browser side of the review page; Bun bundles it through the HTML import in server.ts.

import { align, stripEdges } from "../score.ts";
import type { Candidate } from "./select.ts";

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const audio = $<HTMLAudioElement>("audio");
const textarea = $<HTMLTextAreaElement>("text");
let clips: Candidate[] = [];
let saved: Record<string, string> = {};
let index = 0;

const ALTS = [
	["grok+keyterms", "grok"],
	["Wispr asrText", "asr"],
	["Wispr formattedText", "formatted"],
] as const;

/** One body per alternative of the current clip, redrawn on each keystroke. */
let altBodies: { el: HTMLElement; text: string }[] = [];

const savedCount = () => clips.filter((c) => c.id in saved).length;

// Compare words without case or edge punctuation, so commas and capitals do not flood the diff.
const tokens = (s: string) => s.split(/\s+/).filter(Boolean);
const key = (w: string) => stripEdges(w).toLowerCase();

/** Draws `other` against the owner's text: words only in `other` are marked, the owner's words it lacks are struck. */
function renderDiff(el: HTMLElement, mine: string, other: string) {
	const a = tokens(mine);
	const b = tokens(other);
	const nodes: Node[] = [];
	const word = (tag: "mark" | "del" | null, text: string) => {
		if (tag) {
			const node = document.createElement(tag);
			node.textContent = text;
			nodes.push(node);
		} else nodes.push(document.createTextNode(text));
		nodes.push(document.createTextNode(" "));
	};
	let i = 0;
	let j = 0;
	for (const o of align(a.map(key), b.map(key))) {
		if (o.op === "ok") {
			word(null, b[j++]!);
			i++;
		} else if (o.op === "sub") {
			word("del", a[i++]!);
			word("mark", b[j++]!);
		} else if (o.op === "del") word("del", a[i++]!);
		else word("mark", b[j++]!);
	}
	el.replaceChildren(...nodes);
}

function refreshDiffs() {
	for (const { el, text } of altBodies) renderDiff(el, textarea.value, text);
}

function buildAlts(clip: Candidate) {
	altBodies = [];
	const cards = ALTS.map(([label, field]) => {
		const text = clip[field];
		const card = document.createElement("div");
		card.className = "alt";
		const head = document.createElement("div");
		head.className = "alt-head";
		const name = document.createElement("span");
		name.textContent = label;
		const use = document.createElement("button");
		use.textContent = "Use this";
		use.disabled = !text;
		use.addEventListener("click", () => {
			textarea.value = text ?? "";
			fit();
			refreshDiffs();
			textarea.focus();
		});
		head.append(name, use);
		const body = document.createElement("div");
		body.className = "alt-text";
		if (text) altBodies.push({ el: body, text });
		else {
			body.textContent = "No transcript";
			body.classList.add("empty");
		}
		card.append(head, body);
		return card;
	});
	$("alts").replaceChildren(...cards);
	refreshDiffs();
}

function renderProgress() {
	const strong = document.createElement("strong");
	strong.textContent = `${Math.min(index + 1, clips.length)} / ${clips.length}`;
	$("progress").replaceChildren(strong, ` · ${savedCount()} saved`);
}

/** Grows the text box with its content, so a long clip's text is visible without inner scrolling. */
function fit() {
	textarea.style.height = "auto";
	textarea.style.height = `${textarea.scrollHeight + 2}px`;
}

function setStatus(msg: string, error = false) {
	$("status").textContent = msg;
	$("status").classList.toggle("error", error);
}

function show(i: number) {
	index = i;
	renderProgress();
	window.scrollTo(0, 0);
	const clip = clips[index];
	if (!clip) {
		$("clip").hidden = true;
		$("done").hidden = false;
		$("done-summary").textContent =
			`${savedCount()} of ${clips.length} saved. Skipped clips stay open: go back to them with Back, or start again from the first clip.`;
		audio.removeAttribute("src");
		return;
	}
	$("done").hidden = true;
	$("clip").hidden = false;
	$("app").textContent = clip.app ?? "unknown";
	$("duration").textContent = `${clip.duration.toFixed(1)} s (${clip.bucket})`;
	const isSaved = clip.id in saved;
	$("badge").textContent = isSaved ? "Saved" : "Not saved";
	$("badge").className = `badge ${isSaved ? "saved" : "unsaved"}`;
	textarea.value = saved[clip.id] ?? clip.mai;
	fit();
	audio.src = `/audio/${clip.id}.wav`;
	$<HTMLButtonElement>("back").disabled = index === 0;
	setStatus("");
	buildAlts(clip);
	(document.activeElement as HTMLElement | null)?.blur();
}

async function save() {
	const clip = clips[index];
	if (!clip) return;
	const text = textarea.value.trim();
	if (!text) {
		setStatus("The text is empty. Use Skip for a clip with no speech.", true);
		return;
	}
	const button = $<HTMLButtonElement>("save");
	button.disabled = true;
	try {
		const res = await fetch("/api/save", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({ clipId: clip.id, text }),
		});
		const body = (await res.json().catch(() => ({}))) as { text?: string; error?: string };
		if (!res.ok) throw new Error(body.error ?? res.statusText);
		saved[clip.id] = body.text ?? text;
		show(index + 1);
	} catch (err) {
		setStatus(`Not saved: ${(err as Error).message}. Is the server still running?`, true);
	} finally {
		button.disabled = false;
	}
}

function setRate(rate: number) {
	// defaultPlaybackRate survives the reload that a new src causes.
	audio.defaultPlaybackRate = audio.playbackRate = rate;
	$("rate").textContent = `${rate}x`;
}

let pending: ReturnType<typeof setTimeout> | undefined;
textarea.addEventListener("input", () => {
	fit();
	clearTimeout(pending);
	pending = setTimeout(refreshDiffs, 150);
});
window.addEventListener("resize", fit);
$("save").addEventListener("click", save);
$("skip").addEventListener("click", () => show(index + 1));
$("back").addEventListener("click", () => show(Math.max(0, index - 1)));
$("restart").addEventListener("click", () => show(0));
// The page keys drive the player; a focused native player would act on them twice.
audio.addEventListener("focus", () => audio.blur());

const help = $<HTMLDetailsElement>("help");
try {
	if (localStorage.getItem("review.help") === "closed") help.open = false;
} catch {}
help.addEventListener("toggle", () => {
	try {
		localStorage.setItem("review.help", help.open ? "open" : "closed");
	} catch {}
});

document.addEventListener("keydown", (e) => {
	if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
		e.preventDefault();
		save();
		return;
	}
	const inText = e.target === textarea;
	if (inText && e.key === "Escape") {
		textarea.blur();
		return;
	}
	// In the text box the audio keys need ⌥, so typing and cursor moves still work.
	if (inText ? !e.altKey : e.altKey || e.metaKey || e.ctrlKey) return;
	if (index >= clips.length) return;
	if (e.code === "Space") {
		e.preventDefault();
		if (audio.paused) audio.play();
		else audio.pause();
	} else if (e.code === "ArrowLeft" || e.code === "ArrowRight") {
		e.preventDefault();
		const right = e.code === "ArrowRight";
		if (e.shiftKey) setRate(right ? 1 : 0.5);
		else audio.currentTime = Math.max(0, Math.min(audio.duration || 0, audio.currentTime + (right ? 2 : -2)));
	}
});

try {
	const res = await fetch("/api/session");
	({ clips, saved } = (await res.json()) as { clips: Candidate[]; saved: Record<string, string> });
	// Resume at the first clip without a saved answer.
	const next = clips.findIndex((c) => !(c.id in saved));
	show(next === -1 ? clips.length : next);
} catch (err) {
	$("progress").textContent = `Could not load the review set: ${(err as Error).message}`;
}
