import { exports } from "cloudflare:workers";
import { encodeBase64Url } from "hono/utils/encode";
import { describe, expect, it } from "vitest";
import { readStreamInfo } from "../src/flac";
import { AzureTranscriber, type TranscribeInput, type Transcriber, type Transcript } from "../src/upstream";
import { account, bearer, dictation, errorCode, flac, harness, signIn } from "./helpers";

/** Records each call and how it ended; answers after `release()` when `hold` is set. */
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
    const audio = flac(12.3, 50_000);
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
    const response = await h.fetch("/v1/transcribe", dictation(token, flac(2), 2, { "X-Kotoba-Phrases": header }));
    expect(response.status).toBe(200);
    expect(upstream.calls[0]?.input.phrases).toEqual(phrases);
  });

  it("falls back to the declared length when the FLAC header has no sample count", async () => {
    const upstream = new RecordingTranscriber({ durationMs: undefined });
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const response = await h.fetch("/v1/transcribe", dictation(token, flac(0), 4.2));
    expect(await response.json()).toMatchObject({ billed_seconds: 5 });
  });

  it("answers out_of_hours and aborts the upstream request when no time is left", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const first = await h.fetch("/v1/transcribe", dictation(token, flac(1200), 1200));
    expect(first.status).toBe(200);
    for (let i = 0; i < 2; i++) {
      expect((await h.fetch("/v1/transcribe", dictation(token, flac(1200), 1200))).status).toBe(200);
    }
    expect((await account(h, token)).seconds_left).toBe(0);
    const refused = await h.fetch("/v1/transcribe", dictation(token, flac(5), 5));
    expect(refused.status).toBe(402);
    expect(await errorCode(refused)).toBe("out_of_hours");
    expect(upstream.calls.at(-1)?.aborted).toBe(true);
  });

  it("lets the last dictation overshoot, and never goes below zero", async () => {
    const h = harness(() => new RecordingTranscriber());
    const { token } = await signIn(h);
    for (const seconds of [1200, 1200, 1190]) {
      expect((await h.fetch("/v1/transcribe", dictation(token, flac(seconds), seconds))).status).toBe(200);
    }
    expect((await account(h, token)).seconds_left).toBe(10);
    // 10 s left: a 20-minute dictation still goes through, and the rest is absorbed.
    expect((await h.fetch("/v1/transcribe", dictation(token, flac(1200), 1200))).status).toBe(200);
    expect(await account(h, token)).toMatchObject({ seconds_left: 0, pack_seconds: 0 });
  });

  it("refuses a request with no token, a damaged token or a revoked session", async () => {
    const h = harness();
    const { token } = await signIn(h);
    const none = await h.fetch("/v1/transcribe", { method: "POST", body: flac(1) });
    expect(none.status).toBe(401);
    const damaged = await h.fetch("/v1/transcribe", dictation(`${token.slice(0, -4)}AAAA`, flac(1), 1));
    expect(await errorCode(damaged)).toBe("signed_out");

    const out = await h.fetch("/v1/sign-out-everywhere", { method: "POST", ...bearer(token) });
    expect(out.status).toBe(204);
    const revoked = await h.fetch("/v1/transcribe", dictation(token, flac(1), 1));
    expect(revoked.status).toBe(401);
    expect((await h.fetch("/v1/account", bearer(token))).status).toBe(401);
    // An ended token cannot end the new sessions again.
    expect((await h.fetch("/v1/sign-out-everywhere", { method: "POST", ...bearer(token) })).status).toBe(401);
  });

  it("checks the media type, the headers and the FLAC magic before any upstream call", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const wav = await h.fetch("/v1/transcribe", dictation(token, flac(1), 1, { "Content-Type": "audio/wav" }));
    expect([wav.status, await errorCode(wav)]).toEqual([415, "unsupported_media_type"]);
    const noSeconds = await h.fetch("/v1/transcribe", dictation(token, flac(1), 0));
    expect(await errorCode(noSeconds)).toBe("bad_request");
    const notFlac = await h.fetch("/v1/transcribe", dictation(token, new Uint8Array(100), 1));
    expect([notFlac.status, await errorCode(notFlac)]).toEqual([400, "bad_audio"]);
    const badPhrases = await h.fetch("/v1/transcribe", dictation(token, flac(1), 1, { "X-Kotoba-Phrases": "%%%" }));
    expect(await errorCode(badPhrases)).toBe("bad_request");
    expect(upstream.calls).toHaveLength(0);
  });

  it("refuses audio past the length and size limits", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const declaredLong = await h.fetch("/v1/transcribe", dictation(token, flac(5), 1201));
    expect([declaredLong.status, await errorCode(declaredLong)]).toEqual([413, "audio_too_long"]);
    // The header says 5 s, the file says 25 minutes: the file wins.
    const fileLong = await h.fetch("/v1/transcribe", dictation(token, flac(1500), 5));
    expect(await errorCode(fileLong)).toBe("audio_too_long");
    expect(upstream.calls).toHaveLength(0);
    // A Content-Length over the limit is refused before the upstream starts.
    const request = dictation(token, flac(5, 5000), 5);
    const large = await h.fetch(
      "/v1/transcribe",
      { ...request, headers: { ...request.headers, "Content-Length": "5042" } },
      { MAX_AUDIO_BYTES: "4000" },
    );
    expect([large.status, await errorCode(large)]).toEqual([413, "audio_too_large"]);
    expect(upstream.calls).toHaveLength(0);
  });

  it("stops a body without Content-Length once it passes the size limit", async () => {
    const upstream = new RecordingTranscriber();
    const h = harness(() => upstream);
    const { token } = await signIn(h);
    const audio = flac(5, 9000);
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        for (let i = 0; i < audio.length; i += 1000) controller.enqueue(audio.slice(i, i + 1000));
        controller.close();
      },
    });
    const response = await h.fetch(
      "/v1/transcribe",
      { ...dictation(token, audio, 5), body: stream },
      {
        MAX_AUDIO_BYTES: "4000",
      },
    );
    expect([response.status, await errorCode(response)]).toEqual([413, "audio_too_large"]);
    expect((await account(h, token)).seconds_left).toBe(3600);
  });

  it("pauses every user once the global daily cap is reached", async () => {
    const h = harness(() => new RecordingTranscriber());
    const { token } = await signIn(h);
    const overrides = { GLOBAL_DAILY_CAP_SECONDS: "30" };
    h.clock.now += 10 * 86_400_000; // A day no other test in this file used.
    expect((await h.fetch("/v1/transcribe", dictation(token, flac(40), 40), overrides)).status).toBe(200);
    const paused = await h.fetch("/v1/transcribe", dictation(token, flac(1), 1), overrides);
    expect([paused.status, await errorCode(paused)]).toEqual([503, "service_paused"]);
    // A new UTC day has a new meter.
    h.clock.now += 86_400_000;
    const nextDay = await h.fetch("/v1/transcribe", dictation(token, flac(1), 1), overrides);
    expect(nextDay.status).toBe(200);
  });

  it("limits dictations a minute per user", async () => {
    const h = harness(() => new RecordingTranscriber());
    const { token } = await signIn(h);
    const statuses: number[] = [];
    for (let i = 0; i < 31; i++) statuses.push((await h.fetch("/v1/transcribe", dictation(token, flac(1), 1))).status);
    expect(statuses.slice(0, 30).every((s) => s === 200)).toBe(true);
    expect(statuses[30]).toBe(429);
  });

  it("does not charge when the upstream fails", async () => {
    const h = harness(() => ({
      transcribe: async () => {
        throw new (await import("../src/upstream")).UpstreamError("failed", "Azure 500");
      },
    }));
    const { token } = await signIn(h);
    const response = await h.fetch("/v1/transcribe", dictation(token, flac(3), 3));
    expect([response.status, await errorCode(response)]).toEqual([502, "upstream_failed"]);
    expect((await account(h, token)).seconds_left).toBe(3600);
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
    expect(readStreamInfo(flac(12.5))).toEqual({ isFlac: true, seconds: 12.5 });
    expect(readStreamInfo(flac(0))).toEqual({ isFlac: true, seconds: undefined });
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
