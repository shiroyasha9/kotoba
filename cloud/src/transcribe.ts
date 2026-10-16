import { Hono } from "hono";
import { decodeBase64Url } from "hono/utils/encode";
import { balanceJson } from "./account";
import type { AppEnv } from "./app";
import { afterPaying, audioLimits, type BalanceSnapshot, holdFor } from "./balance";
import { ApiError, numberVar, signedOut } from "./errors";
import { FLAC_HEAD_BYTES, isAppFormat, readStreamInfo } from "./flac";
import { meterName } from "./meter";
import { requireSession } from "./session";
import { UpstreamError } from "./upstream";

export const MAX_PHRASES = 200;
export const MAX_PHRASE_LENGTH = 100;

export const transcribeRoutes = new Hono<AppEnv>();

/**
 * The hot path. The body is the FLAC file; it streams to the upstream as it arrives. The stated length (STREAMINFO,
 * else X-Kotoba-Audio-Seconds) only decides whether the dictation may start; what it can cost is the byte bound (the
 * byte count at MIN_AUDIO_BYTES_PER_SECOND, capped at MAX_AUDIO_SECONDS), held up to the free balance, and the user
 * pays the upstream's duration, at most the hold. A client that understates the length pays and gets no text. Three
 * gates run in parallel with the upstream request: the user's Balance (the session is not revoked, the stated length
 * is covered), the global daily cap (reserves the byte bound), and the per-user rate limit.
 * When a gate refuses, the upstream request is aborted and the meter gets its seconds back. Payment happens after the
 * response (`waitUntil`).
 */
transcribeRoutes.post("/transcribe", requireSession, async (c) => {
  const { env, req } = c;
  const deps = c.var.deps;
  const now = deps.now();
  const limits = audioLimits(env);
  const { maxBytes, maxSeconds } = limits;

  const type = (req.header("Content-Type") ?? "").split(";")[0]?.trim().toLowerCase();
  if (type !== "audio/flac") {
    throw new ApiError(415, "unsupported_media_type", "Send the audio as audio/flac.");
  }
  const lengthHeader = req.header("Content-Length");
  if (lengthHeader === undefined) {
    throw new ApiError(411, "length_required", "Send Content-Length with the audio.");
  }
  const length = Number(lengthHeader);
  if (!Number.isSafeInteger(length) || length < 0)
    throw new ApiError(400, "bad_request", "Content-Length is not valid.");
  if (length > maxBytes) throw tooLarge(maxBytes);
  // A hint only (for the upstream and for an early refusal), never for money.
  const declaredHeader = req.header("X-Kotoba-Audio-Seconds");
  const declared = declaredHeader === undefined ? undefined : Number(declaredHeader);
  if (declared !== undefined && !(Number.isFinite(declared) && declared > 0)) {
    throw new ApiError(400, "bad_request", "X-Kotoba-Audio-Seconds must be a positive number.");
  }
  if (declared !== undefined && declared > maxSeconds) throw tooLong(maxSeconds);
  const language = parseLanguage(req.header("X-Kotoba-Language"));
  const phrases = parsePhrases(req.header("X-Kotoba-Phrases"));
  const body = req.raw.body;
  if (!body || length === 0) throw new ApiError(400, "bad_audio", "The request has no audio.");

  const reader = body.getReader();
  const head = await readHead(reader, FLAC_HEAD_BYTES);
  const flac = readStreamInfo(concat(head));
  // Only the app's own format: a crafted long file at a low bitrate then has to lie about less.
  if (!isAppFormat(flac)) throw new ApiError(400, "bad_audio", "The audio is not in the app's FLAC format.");
  if (flac.seconds !== undefined && flac.seconds > maxSeconds) throw tooLong(maxSeconds);
  const byteBound = holdFor(length, limits);
  const statedSeconds = flac.seconds ?? declared ?? byteBound;
  const audio = relay(reader, head, length);

  const { userId, generation } = c.var.session;
  const requestId = crypto.randomUUID();
  const balance = env.BALANCE.getByName(userId);
  const meter = env.GLOBAL_METER.getByName(meterName(now));
  const abort = new AbortController();
  const signal = AbortSignal.any([abort.signal, AbortSignal.timeout(numberVar(env, "UPSTREAM_TIMEOUT_MS"))]);

  const upstream = deps.transcriber(env).transcribe(
    {
      audio: audio.stream,
      length,
      language,
      phrases,
      audioSeconds: statedSeconds,
    },
    signal,
  );
  upstream.catch(() => {}); // Awaited below, or abandoned when a gate fails.

  // Gives back what the gates took when the dictation ends without a payment. Both calls are safe for any id.
  let metered = false; // Set as soon as the meter answers, so a gate that throws still gives the seconds back.
  const giveBack = () => {
    c.executionCtx.waitUntil(balance.release(requestId));
    if (metered) c.executionCtx.waitUntil(meter.adjust(-byteBound));
  };

  let before: BalanceSnapshot;
  let hold: number;
  try {
    const [auth, underCap, rate] = await Promise.all([
      balance.authorize(requestId, Math.ceil(statedSeconds), byteBound, generation, now),
      meter.reserve(numberVar(env, "GLOBAL_DAILY_CAP_SECONDS"), byteBound).then((ok) => (metered = ok)),
      env.TRANSCRIBE_LIMITER.limit({ key: userId }),
    ]);
    if (!auth.ok && auth.reason === "signed_out") throw signedOut();
    if (!rate.success) {
      throw new ApiError(429, "rate_limited", "Too many dictations in a minute.", { "Retry-After": "60" });
    }
    if (!underCap) throw new ApiError(503, "service_paused", "kotoba Cloud is paused for today. Try again later.");
    if (!auth.ok && auth.reason === "out_of_hours") {
      throw new ApiError(402, "out_of_hours", "Out of kotoba Cloud hours.");
    }
    if (!auth.ok) throw new ApiError(402, "not_enough_hours", "Not enough kotoba Cloud hours left for this recording.");
    before = auth.balance;
    hold = auth.hold;
  } catch (error) {
    abort.abort();
    giveBack();
    throw error;
  }

  let transcript: Awaited<typeof upstream>;
  try {
    transcript = await upstream;
  } catch (error) {
    giveBack();
    throw upstreamFailure(error, signal, audio.tooLarge(), maxBytes);
  }

  // The upstream's own duration, rounded up, is what the audio cost; the user pays it, at most the hold. Without it
  // the meter keeps the byte bound, as no one knows what the upstream transcribed.
  const { durationMs } = transcript;
  const heard = durationMs === undefined ? hold : Math.max(1, Math.ceil(durationMs / 1000));
  const billed = Math.min(heard, hold);
  const correction = durationMs === undefined ? 0 : heard - byteBound;
  c.executionCtx.waitUntil(
    Promise.all([balance.settle(requestId, billed, now), correction && meter.adjust(correction)]).then(([after]) => {
      // No audio and no text in logs: user, seconds and outcome only.
      console.log(
        JSON.stringify({ event: "transcribe", user: userId, billed, heard, seconds_left: after.secondsLeft }),
      );
    }),
  );
  // More audio than the bytes can hold at the lowest allowed bitrate: a crafted file, or a muted microphone. The user
  // pays the hold and gets no text, so a file built to dictate for less than it costs gains nothing.
  if (heard > byteBound) {
    throw new ApiError(400, "bad_audio", "This recording is too quiet or too compressed to transcribe.");
  }
  // More audio than the stated length, which let the dictation start: paid all the same, but no text, so understating
  // the length to start past the balance gains nothing. The tolerance covers honest rounding between encoders. With
  // no duration to check, a hold the balance cut gives no text either.
  const understated = durationMs === undefined ? hold < byteBound : durationMs > (statedSeconds * 1.05 + 2) * 1000;
  if (understated) {
    throw new ApiError(400, "length_mismatch", "The recording is longer than it says. Update kotoba and try again.");
  }
  return c.json({
    text: transcript.text,
    billed_seconds: billed,
    // An estimate: the payment runs after this response. GET /v1/account has the settled numbers.
    ...balanceJson(afterPaying(before, billed)),
  });
});

/** Text cleanup through the relay is not built yet; the app keeps its own cleanup route for now. */
transcribeRoutes.post("/cleanup", requireSession, () => {
  throw new ApiError(501, "not_implemented", "Cleanup through kotoba Cloud is not available yet.");
});

function upstreamFailure(error: unknown, signal: AbortSignal, overLimit: boolean, maxBytes: number): unknown {
  if (overLimit) return tooLarge(maxBytes);
  if (error instanceof UpstreamError) {
    switch (error.kind) {
      case "busy":
        return new ApiError(503, "upstream_busy", "The speech service is busy. Try again.", {
          "Retry-After": error.retryAfter ?? "5",
        });
      case "bad_audio":
        return new ApiError(400, "bad_audio", "The speech service could not read this audio.");
      case "failed":
        console.error(JSON.stringify({ event: "upstream_failed", detail: error.message }));
        return new ApiError(502, "upstream_failed", "The speech service failed. Try again.");
    }
  }
  if (signal.aborted && (signal.reason as Error | undefined)?.name === "TimeoutError") {
    return new ApiError(504, "upstream_timeout", "The speech service did not answer in time.");
  }
  return error;
}

function tooLong(maxSeconds: number): ApiError {
  return new ApiError(413, "audio_too_long", `A dictation can be at most ${maxSeconds / 60} minutes.`);
}

function tooLarge(maxBytes: number): ApiError {
  return new ApiError(413, "audio_too_large", `The audio can be at most ${Math.floor(maxBytes / 1048576)} MB.`);
}

function parseLanguage(value: string | undefined): string | undefined {
  if (value === undefined || value === "") return undefined;
  if (!/^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(value)) {
    throw new ApiError(400, "bad_request", "X-Kotoba-Language must be a language code such as en.");
  }
  return value;
}

/** `X-Kotoba-Phrases`: base64url of a UTF-8 JSON array of strings. */
function parsePhrases(value: string | undefined): string[] {
  if (value === undefined || value === "") return [];
  let phrases: unknown;
  try {
    phrases = JSON.parse(new TextDecoder().decode(decodeBase64Url(value)));
  } catch {
    phrases = undefined;
  }
  const valid =
    Array.isArray(phrases) &&
    phrases.length <= MAX_PHRASES &&
    phrases.every((p) => typeof p === "string" && p.length > 0 && p.length <= MAX_PHRASE_LENGTH);
  if (!valid) {
    throw new ApiError(
      400,
      "bad_request",
      `X-Kotoba-Phrases must be base64url JSON: at most ${MAX_PHRASES} strings of 1-${MAX_PHRASE_LENGTH} characters.`,
    );
  }
  return phrases as string[];
}

/** Reads chunks until `bytes` have come (or the body ends). The chunks are relayed as they are, not copied. */
async function readHead(reader: ReadableStreamDefaultReader<Uint8Array>, bytes: number): Promise<Uint8Array[]> {
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (total < bytes) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.byteLength;
  }
  return chunks;
}

function concat(chunks: Uint8Array[]): Uint8Array {
  if (chunks.length === 1 && chunks[0]) return chunks[0];
  const out = new Uint8Array(chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0));
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

/** The body again, `head` first, failing once it passes `maxBytes` (the declared length), so the hold stays a bound. */
function relay(reader: ReadableStreamDefaultReader<Uint8Array>, head: Uint8Array[], maxBytes: number) {
  let sent = 0;
  let overLimit = false;
  const stream = new ReadableStream<Uint8Array>(
    {
      async pull(controller) {
        const next = head.shift() ?? (await reader.read()).value;
        if (next === undefined) return controller.close();
        sent += next.byteLength;
        if (sent > maxBytes) {
          overLimit = true;
          controller.error(tooLarge(maxBytes));
          await reader.cancel();
          return;
        }
        controller.enqueue(next);
      },
      cancel(reason) {
        return reader.cancel(reason);
      },
    },
    { highWaterMark: 0 },
  );
  return { stream, tooLarge: () => overLimit };
}
