import { exports } from "cloudflare:workers";
import { encodeBase64Url } from "hono/utils/encode";
import { describe, expect, it } from "vitest";
import { APP_FORMAT, readStreamInfo } from "../src/flac";
import {
  AzureTranscriber,
  type TranscribeInput,
  type Transcriber,
  type Transcript,
  UpstreamError,
} from "../src/upstream";
import {
  account,
  bearer,
  DAY,
  dictation,
  errorCode,
  flac,
  harness,
  holdOf,
  meterSeconds,
  signIn,
  speech,
} from "./helpers";

/** Records each call and how it ended. */
class RecordingTranscriber implements Transcriber {
  calls: { input: Omit<TranscribeInput, "audio">; bytes: number; aborted: boolean }[] = [];
  constructor(private readonly reply: Partial<Transcript> = {}) {}

  async transcribe(input: TranscribeInput, signal: AbortSignal): Promise<Transcript> {
    const { audio, ...rest } = input;
    const call = { input: rest, bytes: 0, aborted: false };
    this.calls.push(call);
    signal.addEventListener("abort", () => {
      call.aborted = true;
    });
    for await (const chunk of audio) call.bytes += chunk.byteLength;
    // Gives the gates time to run first, as a real upstream takes far longer than they do.
    await scheduler.wait(20);
    signal.throwIfAborted();
    return { text: "hello world", durationMs: input.audioSeconds * 1000, ...this.reply };
  }
}

describe("POST /v1/transcribe", () => {
  it("returns the text and pays the upstream's duration, rounded up", async () => {
    const upstream = new RecordingTranscriber({ durationMs: 12_300 });
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const audio = speech(12.3);
    const response = await h.fetch("/v1/transcribe", dictation(token, audio, 12.3, { "X-Kotoba-Language": "en" }));
    expect(response.status).toBe(200);
    const body = await response.json<{ text: string; billed_seconds: number; seconds_left: number }>();
    expect(body).toMatchObject({ text: "hello world", billed_seconds: 13, seconds_left: 3600 - 13 });
    expect(upstream.calls[0]?.bytes).toBe(audio.byteLength);
    expect(upstream.calls[0]?.input).toMatchObject({ language: "en", phrases: [], audioSeconds: 12.3 });
    expect(await account(h, token)).toMatchObject({ seconds_left: 3587, pack_seconds: 3587 });
  });

  it("passes the dictionary terms from X-Kotoba-Phrases", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const phrases = ["kotoba", "Wispr Flow", "नमस्ते"];
    const header = encodeBase64Url(new TextEncoder().encode(JSON.stringify(phrases)).buffer);
    const response = await h.fetch("/v1/transcribe", dictation(token, speech(2), 2, { "X-Kotoba-Phrases": header }));
    expect(response.status).toBe(200);
    expect(upstream.calls[0]?.input.phrases).toEqual(phrases);
  });

  it("lets an honest 5-minute recording through with 10 minutes left", async () => {
    const h = harness(() => new RecordingTranscriber());
    const { token } = await signIn(h, { trialSeconds: 600 });
    const audio = speech(300);
    expect(holdOf(audio)).toBeGreaterThan(600); // The byte bound alone would refuse it.
    const response = await h.fetch("/v1/transcribe", dictation(token, audio, 300));
    expect(response.status).toBe(200);
    expect(await account(h, token)).toMatchObject({ seconds_left: 300 });
  });

  it("charges a lying length at most the balance, then answers out_of_hours", async () => {
    const upstream = new RecordingTranscriber({ durationMs: 25_000 });
    const h = harness(() => upstream);
    const { token } = await signIn(h, { trialSeconds: 20 });
    // About 25 s of audio, but STREAMINFO and the header both say 1 s.
    const audio = flac(1, 180_000);
    const response = await h.fetch("/v1/transcribe", dictation(token, audio, 1));
    expect(await response.json()).toMatchObject({ billed_seconds: 20, seconds_left: 0 });
    expect(await account(h, token)).toMatchObject({ seconds_left: 0 });
    const next = await h.fetch("/v1/transcribe", dictation(token, flac(1, 180_000), 1));
    expect([next.status, await errorCode(next)]).toEqual([402, "out_of_hours"]);
  });

  it("refuses a recording longer than the free seconds before the upload ends", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h, { trialSeconds: 30 });
    expect((await h.fetch("/v1/transcribe", dictation(token, speech(10), 10))).status).toBe(200);
    expect((await account(h, token)).seconds_left).toBe(20);
    const refused = await h.fetch("/v1/transcribe", dictation(token, speech(25), 25));
    expect([refused.status, await errorCode(refused)]).toEqual([402, "not_enough_hours"]);
    expect(upstream.calls.at(-1)?.aborted).toBe(true);
    expect((await h.fetch("/v1/transcribe", dictation(token, speech(2), 2))).status).toBe(200);
    expect((await account(h, token)).seconds_left).toBe(18);

    const { token: empty } = await signIn(h, { trialSeconds: 0 });
    const none = await h.fetch("/v1/transcribe", dictation(empty, speech(2), 2));
    expect([none.status, await errorCode(none)]).toEqual([402, "out_of_hours"]);
  });

  it("refuses FLAC that is not the app's format (16 kHz, mono, 16-bit) before any upstream call", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const formats = [
      { ...APP_FORMAT, channels: 2 },
      { ...APP_FORMAT, sampleRate: 8_000 },
      { ...APP_FORMAT, bitsPerSample: 8 },
    ];
    for (const format of formats) {
      const audio = flac(2, 30_000, format);
      const response = await h.fetch("/v1/transcribe", dictation(token, audio, 2));
      expect([response.status, await errorCode(response)]).toEqual([400, "bad_audio"]);
    }
    expect(upstream.calls).toHaveLength(0);
  });

  it("pays the hold, and keeps the byte bound on the meter, when the upstream gives no duration", async () => {
    const h = harness(() => new RecordingTranscriber({ durationMs: undefined }));
    h.clock.now += 50 * DAY;
    const { token } = await signIn(h, { trialSeconds: 5 });
    const audio = speech(4);
    const response = await h.fetch("/v1/transcribe", dictation(token, audio, 4));
    expect(await response.json()).toMatchObject({ billed_seconds: 5 });
    expect(await meterSeconds(h.clock.now)).toBe(holdOf(audio));
  });

  it("never charges more than the hold, and gives no text when the upstream heard more than the bytes can hold", async () => {
    const h = harness(() => new RecordingTranscriber({ durationMs: 100_000 }));
    const { token } = await signIn(h);
    const audio = speech(2);
    const response = await h.fetch("/v1/transcribe", dictation(token, audio, 2));
    expect([response.status, await errorCode(response)]).toEqual([400, "bad_audio"]);
    expect((await account(h, token)).seconds_left).toBe(3600 - holdOf(audio));
  });

  it("needs Content-Length, so the hold can come from the byte count", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const audio = speech(2);
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(audio);
        controller.close();
      },
    });
    const request = dictation(token, audio, 2);
    const { "Content-Length": _, ...headers } = request.headers;
    const response = await h.fetch("/v1/transcribe", { ...request, headers, body: stream });
    expect([response.status, await errorCode(response)]).toEqual([411, "length_required"]);
    expect(upstream.calls).toHaveLength(0);
  });

  it("refuses a request with no token, a damaged token or a revoked session", async () => {
    const h = harness();
    const { token } = await signIn(h);
    const none = await h.fetch("/v1/transcribe", { method: "POST", body: speech(1) });
    expect(none.status).toBe(401);
    const damaged = await h.fetch("/v1/transcribe", dictation(`${token.slice(0, -4)}AAAA`, speech(1), 1));
    expect(await errorCode(damaged)).toBe("signed_out");

    const out = await h.fetch("/v1/sign-out-everywhere", { method: "POST", ...bearer(token) });
    expect(out.status).toBe(204);
    const revoked = await h.fetch("/v1/transcribe", dictation(token, speech(1), 1));
    expect(revoked.status).toBe(401);
    expect((await h.fetch("/v1/account", bearer(token))).status).toBe(401);
    // An ended token cannot end the new sessions again.
    expect((await h.fetch("/v1/sign-out-everywhere", { method: "POST", ...bearer(token) })).status).toBe(401);
  });

  it("checks the media type, the headers and the FLAC magic before any upstream call", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const wav = await h.fetch("/v1/transcribe", dictation(token, speech(1), 1, { "Content-Type": "audio/wav" }));
    expect([wav.status, await errorCode(wav)]).toEqual([415, "unsupported_media_type"]);
    const badSeconds = await h.fetch(
      "/v1/transcribe",
      dictation(token, speech(1), 1, { "X-Kotoba-Audio-Seconds": "x" }),
    );
    expect(await errorCode(badSeconds)).toBe("bad_request");
    const notFlac = await h.fetch("/v1/transcribe", dictation(token, new Uint8Array(100), 1));
    expect([notFlac.status, await errorCode(notFlac)]).toEqual([400, "bad_audio"]);
    const badPhrases = await h.fetch("/v1/transcribe", dictation(token, speech(1), 1, { "X-Kotoba-Phrases": "%%%" }));
    expect(await errorCode(badPhrases)).toBe("bad_request");
    expect(upstream.calls).toHaveLength(0);
  });

  it("refuses audio past the length and size limits", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const declaredLong = await h.fetch("/v1/transcribe", dictation(token, speech(5), 1201));
    expect([declaredLong.status, await errorCode(declaredLong)]).toEqual([413, "audio_too_long"]);
    // The header says 5 s, the file says 25 minutes: either claim of too long is enough to refuse.
    const fileLong = await h.fetch("/v1/transcribe", dictation(token, flac(1500), 5));
    expect(await errorCode(fileLong)).toBe("audio_too_long");
    const large = await h.fetch("/v1/transcribe", dictation(token, speech(5), 5), { MAX_AUDIO_BYTES: "4000" });
    expect([large.status, await errorCode(large)]).toEqual([413, "audio_too_large"]);
    expect(upstream.calls).toHaveLength(0);
  });

  it("pauses every user once the global daily cap is reached", async () => {
    const h = harness(() => new RecordingTranscriber());
    const { token } = await signIn(h);
    const overrides = { GLOBAL_DAILY_CAP_SECONDS: "30" };
    h.clock.now += 10 * DAY; // A day no other test in this file used.
    expect((await h.fetch("/v1/transcribe", dictation(token, speech(40), 40), overrides)).status).toBe(200);
    const paused = await h.fetch("/v1/transcribe", dictation(token, speech(1), 1), overrides);
    expect([paused.status, await errorCode(paused)]).toEqual([503, "service_paused"]);
    // A new UTC day has a new meter.
    h.clock.now += DAY;
    const nextDay = await h.fetch("/v1/transcribe", dictation(token, speech(1), 1), overrides);
    expect(nextDay.status).toBe(200);
  });

  it("gives the global meter back when a gate refuses, so refused requests cannot use up the cap", async () => {
    const h = harness(() => new RecordingTranscriber());
    h.clock.now += 20 * DAY;
    const overrides = { GLOBAL_DAILY_CAP_SECONDS: "30" };
    const { token: broke } = await signIn(h, { trialSeconds: 0 });
    for (let i = 0; i < 2; i++) {
      const refused = await h.fetch("/v1/transcribe", dictation(broke, speech(10), 10), overrides);
      expect(await errorCode(refused)).toBe("out_of_hours");
    }
    expect(await meterSeconds(h.clock.now)).toBe(0);
    const { token } = await signIn(h);
    expect((await h.fetch("/v1/transcribe", dictation(token, speech(2), 2), overrides)).status).toBe(200);
  });

  it("counts the byte bound on the global meter, then corrects it to the upstream's duration", async () => {
    let meterDuringCall = -1;
    const h = harness(() => ({
      async transcribe(input, signal) {
        for await (const _ of input.audio);
        await scheduler.wait(20);
        meterDuringCall = await meterSeconds(h.clock.now);
        signal.throwIfAborted();
        return { text: "hi", durationMs: 12_000 };
      },
    }));
    h.clock.now += 30 * DAY;
    const { token } = await signIn(h);
    // STREAMINFO and the header claim 1 s; the bytes can hold 30 s.
    const audio = flac(1, 180_000);
    expect((await h.fetch("/v1/transcribe", dictation(token, audio, 1))).status).toBe(200);
    expect(meterDuringCall).toBe(holdOf(audio));
    expect(await meterSeconds(h.clock.now)).toBe(12);
  });

  it("limits dictations a minute per user", async () => {
    const h = harness(() => new RecordingTranscriber());
    const { token } = await signIn(h);
    const statuses: number[] = [];
    for (let i = 0; i < 31; i++)
      statuses.push((await h.fetch("/v1/transcribe", dictation(token, speech(1), 1))).status);
    expect(statuses.slice(0, 30).every((s) => s === 200)).toBe(true);
    expect(statuses[30]).toBe(429);
  });

  it("does not charge the user or the global meter when the upstream fails", async () => {
    const h = harness(() => ({
      transcribe: async () => {
        throw new UpstreamError("failed", "Azure 500");
      },
    }));
    h.clock.now += 40 * DAY;
    const { token } = await signIn(h);
    const response = await h.fetch("/v1/transcribe", dictation(token, speech(3), 3));
    expect([response.status, await errorCode(response)]).toEqual([502, "upstream_failed"]);
    expect((await account(h, token)).seconds_left).toBe(3600);
    expect(await meterSeconds(h.clock.now)).toBe(0);
  });

  it("answers 501 for cleanup, which is not built yet", async () => {
    const h = harness();
    const { token } = await signIn(h);
    const response = await h.fetch("/v1/cleanup", { method: "POST", ...bearer(token) });
    expect([response.status, await errorCode(response)]).toEqual([501, "not_implemented"]);
  });
});

describe("AzureTranscriber", () => {
  function azure(respond: (request: Request) => Response | Promise<Response>) {
    const seen: Request[] = [];
    const fetcher = async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      seen.push(request);
      return respond(request);
    };
    return { seen, transcriber: new AzureTranscriber("https://kotoba.example.com/", "key-1", fetcher as typeof fetch) };
  }

  function input(audio: Uint8Array, extra: Partial<TranscribeInput> = {}): TranscribeInput {
    return {
      audio: new Blob([audio]).stream(),
      length: audio.byteLength,
      language: "en",
      phrases: ["kotoba"],
      audioSeconds: 3,
      ...extra,
    };
  }

  it("sends the definition and the audio as multipart, with the key and a fixed model", async () => {
    let form: FormData | undefined;
    const { seen, transcriber } = azure(async (request) => {
      form = await request.formData();
      return Response.json({ durationMilliseconds: 3040, combinedPhrases: [{ text: "Hello there." }] });
    });
    const audio = flac(3, 1000);
    const result = await transcriber.transcribe(input(audio), new AbortController().signal);
    expect(result).toEqual({ text: "Hello there.", durationMs: 3040 });
    const request = seen[0];
    expect(request?.url).toBe(
      "https://kotoba.example.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15",
    );
    expect(request?.headers.get("Ocp-Apim-Subscription-Key")).toBe("key-1");
    expect(JSON.parse(String(form?.get("definition")))).toEqual({
      enhancedMode: { enabled: true, model: "MAI-Transcribe-2" },
      locales: ["en"],
      phraseList: { phrases: ["kotoba"] },
    });
    const file = form?.get("audio") as File;
    expect(new Uint8Array(await file.arrayBuffer())).toEqual(audio);
  });

  it("maps Azure errors to upstream error kinds", async () => {
    const cases: [Response, string, string | undefined][] = [
      [
        Response.json({ error: { code: "TooManyRequests" } }, { status: 429, headers: { "Retry-After": "7" } }),
        "busy",
        "7",
      ],
      [
        Response.json({ error: { code: "InvalidRequest", innerError: { code: "EmptyAudioFile" } } }, { status: 400 }),
        "bad_audio",
        undefined,
      ],
      [Response.json({ error: { code: "Unauthorized" } }, { status: 401 }), "failed", undefined],
      [new Response("oops", { status: 500 }), "failed", undefined],
    ];
    for (const [response, kind, retryAfter] of cases) {
      const { transcriber } = azure(() => response);
      await expect(transcriber.transcribe(input(flac(1)), new AbortController().signal)).rejects.toMatchObject({
        kind,
        retryAfter,
      });
    }
  });
});

describe("readStreamInfo", () => {
  it("reads the length from STREAMINFO, and tells FLAC from other bytes", () => {
    const format = { isFlac: true, ...APP_FORMAT };
    expect(readStreamInfo(flac(12.5))).toEqual({ ...format, seconds: 12.5 });
    expect(readStreamInfo(flac(0))).toEqual({ ...format, seconds: undefined });
    expect(readStreamInfo(new Uint8Array(64)).isFlac).toBe(false);
  });
});

describe("the deployed Worker", () => {
  it("serves the API with its default dependencies", async () => {
    const response = await exports.default.fetch("https://cloud.test/v1/account");
    expect([response.status, await errorCode(response)]).toEqual([401, "signed_out"]);
    const missing = await exports.default.fetch("https://cloud.test/nope");
    expect(missing.status).toBe(404);
  });
});
