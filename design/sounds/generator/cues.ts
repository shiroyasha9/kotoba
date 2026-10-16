// Writes kotoba's sound cues into App/Sounds: for each voice in `voices`, <voice>-DictationStart.caf and
// <voice>-DictationStop.caf (the names `CueVoice.soundName` reads). The owner picks the voice in General.
// Needs bun and afconvert (ships with macOS). Run from anywhere: bun generator/cues.ts [folder]
// A folder argument writes them there instead.
//
// The cues are kotoba's own: every file in /System/Library/Sounds is also a choice of system alert sound (Tink is the
// default one, "Boop"), so a cue taken from there can sound exactly like the alert beep of the focused app.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { $ } from "bun";

const rate = 48_000;
/** Peak level, near the system sounds (Tink peaks at -8.8 dBFS, Pop at -11.1). */
const peakDBFS = -10;
const seconds = 0.55;
/** The second note of each cue starts this long after the first. */
const gap = 0.09;

type Voice = {
  /** The start cue rises from `low` to `high`; the stop cue falls. */
  low: number;
  high: number;
  /** How long a note takes to fall to 1/e, in seconds. */
  decay: number;
  /** Low-pass cutoffs in Hz: one pole on the pluck's noise (a soft finger vs a pick), two on the whole cue (warmth). */
  pluck: number;
  tone: number;
};

// The cases of `CueVoice`.
const voices = {
  // The default: E3 to B3, a soft nylon pluck.
  nylon: { low: 164.81, high: 246.94, decay: 0.2, pluck: 1_200, tone: 1_400 },
  // A fifth lower, A2 to E3, for more bass.
  low: { low: 110, high: 164.81, decay: 0.22, pluck: 900, tone: 1_000 },
  // E3 to B3 with a brighter, longer-ringing steel string.
  steel: { low: 164.81, high: 246.94, decay: 0.25, pluck: 4_000, tone: 3_000 },
} satisfies Record<string, Voice>;

/** A fixed seed, so a run writes the same files. */
function random(seed: number): () => number {
  let s = seed;
  return () => {
    s = (s * 1_664_525 + 1_013_904_223) >>> 0;
    return s / 2 ** 31 - 1;
  };
}

/** One-pole low-pass in place. */
function lowPass(samples: Float32Array, hz: number) {
  const a = 1 - Math.exp((-2 * Math.PI * hz) / rate);
  let y = 0;
  for (let i = 0; i < samples.length; i++) {
    y += a * (samples[i] - y);
    samples[i] = y;
  }
}

/** Karplus-Strong: a delay line one period long, filled with low-passed noise, averaged and damped each period. */
function pluck(out: Float32Array, hz: number, at: number, voice: Voice, noise: () => number) {
  // Each sample comes back as the average of itself and the next, one period later: a loop of period - 0.5 samples.
  const period = Math.max(2, Math.round(rate / hz + 0.5));
  const line = new Float32Array(period).map(noise);
  lowPass(line, voice.pluck);
  const loss = Math.exp(-(period - 0.5) / rate / voice.decay);
  const start = Math.round(at * rate);
  for (let i = start, k = 0; i < out.length; i++, k = (k + 1) % period) {
    const next = (k + 1) % period;
    out[i] += line[k];
    line[k] = loss * 0.5 * (line[k] + line[next]);
  }
}

function render(notes: number[], voice: Voice): Float32Array {
  const out = new Float32Array(Math.round(seconds * rate));
  const noise = random(7);
  notes.forEach((hz, i) => pluck(out, hz, i * gap, voice, noise));
  lowPass(out, voice.tone);
  lowPass(out, voice.tone);
  // A 3 ms attack takes the click off the pluck; the last 60 ms fade to silence.
  const attack = Math.round(0.003 * rate);
  const fade = Math.round(0.06 * rate);
  for (let i = 0; i < attack; i++) out[i] *= i / attack;
  for (let i = 0; i < fade; i++) out[out.length - 1 - i] *= i / fade;
  const peak = out.reduce((m, x) => Math.max(m, Math.abs(x)), 0);
  const scale = 10 ** (peakDBFS / 20) / peak;
  return out.map((x) => x * scale);
}

/** 16-bit mono PCM WAV. */
function wav(samples: Float32Array): Uint8Array {
  const data = samples.length * 2;
  const view = new DataView(new ArrayBuffer(44 + data));
  const text = (at: number, s: string) => [...s].forEach((c, i) => view.setUint8(at + i, c.charCodeAt(0)));
  text(0, "RIFF");
  view.setUint32(4, 36 + data, true);
  text(8, "WAVEfmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, rate, true);
  view.setUint32(28, rate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  text(36, "data");
  view.setUint32(40, data, true);
  samples.forEach((x, i) => view.setInt16(44 + i * 2, Math.round(x * 32_767), true));
  return new Uint8Array(view.buffer);
}

async function write(name: string, voice: Voice, outDir: string) {
  mkdirSync(outDir, { recursive: true });
  const cues = { DictationStart: [voice.low, voice.high], DictationStop: [voice.high, voice.low] };
  const work = mkdtempSync(join(tmpdir(), "kotoba-cues-"));
  try {
    for (const [cue, notes] of Object.entries(cues)) {
      const source = join(work, `${cue}.wav`);
      writeFileSync(source, wav(render(notes, voice)));
      await $`afconvert -f caff -d LEI16 ${source} ${join(outDir, `${name}-${cue}.caf`)}`;
    }
  } finally {
    rmSync(work, { recursive: true });
  }
}

const outDir = process.argv[2] ? resolve(process.argv[2]) : join(import.meta.dir, "..", "..", "..", "App", "Sounds");
for (const [name, voice] of Object.entries(voices)) await write(name, voice, outDir);
