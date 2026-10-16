/**
 * The relay's own overhead, measured locally: the same dictation sent (a) straight to the fake Azure, as the app's
 * BYOK route sends it, and (b) through `wrangler dev` (AzureTranscriber -> the same fake Azure). Pairs alternate their
 * order; the paired difference is the relay's cost: token check, the three gates, the streamed multipart and one more
 * local HTTP hop. No network, no paid call.
 * Usage: `bun run latency [pairs per size, default 200]`. Raw samples go to .wrangler/bench-latency.json.
 */
import { rmSync } from "node:fs";
import { flac } from "../test/flac";
import { serveFakeAzure } from "./fake-azure";

const PAIRS = Number(process.argv[2] ?? 200);
const WARMUP = 20;
const RELAY_PORT = 8787;
const AZURE_PORT = 8788;
const STATE = ".wrangler/bench-state";
const CONFIG = "wrangler.bench.jsonc";
/** 16 kHz mono speech in FLAC is about 18 KB a second. */
const BYTES_PER_SECOND = 18_000;
const SIZES = [2, 10, 30];
const PHRASES = Array.from({ length: 50 }, (_, i) => `term${i}`);

const fakeAzure = serveFakeAzure(AZURE_PORT);

// The bench config: wrangler.jsonc with the per-user rate limit lifted (a person sends 30 a minute, the bench more).
const config = (await Bun.file("wrangler.jsonc").text()).replace(/"limit": 30\b/, '"limit": 1000000');
await Bun.write(CONFIG, config);
rmSync(STATE, { recursive: true, force: true });
const migrate = Bun.spawnSync(
  ["bunx", "wrangler", "d1", "migrations", "apply", "DB", "--local", "--persist-to", STATE, "-c", CONFIG],
  { env: { ...process.env, CI: "1" } },
);
if (migrate.exitCode !== 0) throw new Error(`migrations failed: ${migrate.stderr.toString()}`);

const vars = {
  UPSTREAM: "azure",
  AZURE_ENDPOINT: `http://127.0.0.1:${AZURE_PORT}`,
  TRIAL_SECONDS: "100000000",
  GLOBAL_DAILY_CAP_SECONDS: "1000000000",
};
const relay = Bun.spawn(
  [
    "bunx",
    "wrangler",
    "dev",
    "-c",
    CONFIG,
    "--port",
    String(RELAY_PORT),
    "--ip",
    "127.0.0.1",
    "--env-file",
    ".dev.vars.example",
    "--persist-to",
    STATE,
    "--show-interactive-dev-session=false",
    ...Object.entries(vars).flatMap(([key, value]) => ["--var", `${key}:${value}`]),
  ],
  { stdout: "pipe", stderr: "inherit" },
);

// Lines from wrangler dev: "Ready on ..." first, later the console mailer's sign-in code.
const waiters: { match: RegExp; resolve: (m: RegExpMatchArray) => void }[] = [];
const waitFor = (match: RegExp) => new Promise<RegExpMatchArray>((resolve) => waiters.push({ match, resolve }));
(async () => {
  const decoder = new TextDecoder();
  let buffer = "";
  for await (const chunk of relay.stdout) {
    buffer += decoder.decode(chunk);
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      for (const waiter of [...waiters]) {
        const m = line.match(waiter.match);
        if (m) {
          waiters.splice(waiters.indexOf(waiter), 1);
          waiter.resolve(m);
        }
      }
    }
  }
})();

try {
  await waitFor(/Ready on/);
  const base = `http://127.0.0.1:${RELAY_PORT}`;
  const email = "bench@example.com";
  const codeLine = waitFor(/sign-in code for \S+: (\d{6})/);
  await post(`${base}/auth/start`, { email });
  const code = (await codeLine)[1];
  const { token } = (await post(`${base}/auth/verify`, { email, code })) as { token: string };

  const phrasesHeader = Buffer.from(JSON.stringify(PHRASES)).toString("base64url");
  const results: Record<string, { direct: number[]; relay: number[] }> = {};
  for (const seconds of SIZES) {
    const audio = flac(seconds, seconds * BYTES_PER_SECOND);
    const direct = async () => {
      const form = new FormData();
      form.append(
        "definition",
        JSON.stringify({
          enhancedMode: { enabled: true, model: "MAI-Transcribe-2" },
          locales: ["en"],
          phraseList: { phrases: PHRASES },
        }),
      );
      form.append("audio", new Blob([audio], { type: "audio/flac" }), "audio.flac");
      return timed(`http://127.0.0.1:${AZURE_PORT}/speechtotext/transcriptions:transcribe?api-version=2025-10-15`, {
        method: "POST",
        headers: { "Ocp-Apim-Subscription-Key": "azure-test-key" },
        body: form,
      });
    };
    const viaRelay = () =>
      timed(`${base}/v1/transcribe`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "audio/flac",
          "X-Kotoba-Audio-Seconds": String(seconds),
          "X-Kotoba-Language": "en",
          "X-Kotoba-Phrases": phrasesHeader,
        },
        body: audio,
      });
    for (let i = 0; i < WARMUP; i++) {
      await direct();
      await viaRelay();
    }
    const sample = { direct: [] as number[], relay: [] as number[] };
    for (let i = 0; i < PAIRS; i++) {
      if (i % 2 === 0) {
        sample.direct.push(await direct());
        sample.relay.push(await viaRelay());
      } else {
        sample.relay.push(await viaRelay());
        sample.direct.push(await direct());
      }
    }
    results[`${seconds}s`] = sample;
  }
  await Bun.write(".wrangler/bench-latency.json", JSON.stringify(results));

  console.log(`\npairs per size: ${PAIRS} (after ${WARMUP} warm-up pairs); times in ms`);
  console.log("audio  bytes    direct p50/p90   relay p50/p90   overhead p50/p90");
  for (const seconds of SIZES) {
    const sample = results[`${seconds}s`];
    if (!sample) continue;
    const overhead = sample.relay.map((r, i) => r - (sample.direct[i] ?? 0));
    const row = [sample.direct, sample.relay, overhead].map((xs) => `${fmt(pct(xs, 50))} / ${fmt(pct(xs, 90))}`);
    console.log(
      `${`${seconds}s`.padEnd(6)} ${String(seconds * BYTES_PER_SECOND + 42).padEnd(8)} ${row[0]?.padEnd(16)} ${row[1]?.padEnd(15)} ${row[2]}`,
    );
  }
} finally {
  relay.kill();
  fakeAzure.stop(true);
}

async function post(url: string, body: unknown): Promise<unknown> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${url}: ${response.status} ${await response.text()}`);
  return response.json();
}

/** Milliseconds from send to the whole response body read. Throws on a non-200, so a failure never counts as fast. */
async function timed(url: string, init: RequestInit): Promise<number> {
  const start = performance.now();
  const response = await fetch(url, init);
  const text = await response.text();
  const ms = performance.now() - start;
  if (!response.ok) throw new Error(`${url}: ${response.status} ${text}`);
  return ms;
}

function pct(xs: number[], p: number): number {
  const sorted = [...xs].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))] ?? Number.NaN;
}

function fmt(ms: number): string {
  return ms.toFixed(1);
}
