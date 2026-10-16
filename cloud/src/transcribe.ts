import { Hono } from "hono";
import { decodeBase64Url } from "hono/utils/encode";
import { balanceJson } from "./account";
import type { AppEnv } from "./app";
import { afterPaying, type BalanceSnapshot } from "./balance";
import { ApiError, numberVar, signedOut } from "./errors";
import { FLAC_HEAD_BYTES, readStreamInfo } from "./flac";
import { meterName } from "./meter";
import { requireSession } from "./session";
import { UpstreamError } from "./upstream";

export const MAX_PHRASES = 200;
export const MAX_PHRASE_LENGTH = 100;

export const transcribeRoutes = new Hono<AppEnv>();

/**
 * The hot path. The body is the FLAC file; it streams to the upstream as it arrives. Three gates run in parallel with
 * the upstream request: the user's Balance (hours left, session not revoked), the global daily cap, and the per-user
 * rate limit. When a gate fails the upstream request is aborted. Payment happens after the response (`waitUntil`).
 */
transcribeRoutes.post("/transcribe", requireSession, async (c) => {
  const { env, req } = c;
  const deps = c.var.deps;
  const now = deps.now();
  const maxBytes = numberVar(env, "MAX_AUDIO_BYTES");
  const maxSeconds = numberVar(env, "MAX_AUDIO_SECONDS");

  const type = (req.header("Content-Type") ?? "").split(";")[0]?.trim().toLowerCase();
  if (type !== "audio/flac") {
    throw new ApiError(415, "unsupported_media_type", "Send the audio as audio/flac.");
  }
  const declared = Number(req.header("X-Kotoba-Audio-Seconds"));
  if (!Number.isFinite(declared) || declared <= 0) {
    throw new ApiError(400, "bad_request", "X-Kotoba-Audio-Seconds must be a positive number.");
  }
  if (declared > maxSeconds) throw tooLong(maxSeconds);
  const lengthHeader = req.header("Content-Length");
  const length = lengthHeader === undefined ? undefined : Number(lengthHeader);
  if (length !== undefined && length > maxBytes) throw tooLarge(maxBytes);
  const language = parseLanguage(req.header("X-Kotoba-Language"));
  const phrases = parsePhrases(req.header("X-Kotoba-Phrases"));
  const body = req.raw.body;
  if (!body) throw new ApiError(400, "bad_audio", "The request has no audio.");

  const reader = body.getReader();
  const head = await readHead(reader, FLAC_HEAD_BYTES);
  const flac = readStreamInfo(concat(head));
  if (!flac.isFlac) throw new ApiError(400, "bad_audio", "The audio is not a FLAC file.");
  if (flac.seconds !== undefined && flac.seconds > maxSeconds) throw tooLong(maxSeconds);
  const audioSeconds = flac.seconds ?? declared;
  // With no sample count in the file the client's length is only a claim: hold the most a dictation can be.
  const holdSeconds = Math.ceil(flac.seconds ?? maxSeconds);
  const audio = relay(reader, head, maxBytes);

  const { userId, generation } = c.var.session;
  const requestId = crypto.randomUUID();
  const balance = env.BALANCE.getByName(userId);
  const meter = env.GLOBAL_METER.getByName(meterName(now));
  const abort = new AbortController();
  const signal = AbortSignal.any([abort.signal, AbortSignal.timeout(numberVar(env, "UPSTREAM_TIMEOUT_MS"))]);

  const upstream = deps
    .transcriber(env)
    .transcribe({ audio: audio.stream, length, language, phrases, audioSeconds }, signal);
  upstream.catch(() => {}); // Awaited below, or abandoned when a gate fails.

  let before: BalanceSnapshot;
  try {
    const [auth, underCap, rate] = await Promise.all([
      balance.authorize(requestId, holdSeconds, generation, now),
      meter.charge(numberVar(env, "GLOBAL_DAILY_CAP_SECONDS"), Math.ceil(audioSeconds)),
      env.TRANSCRIBE_LIMITER.limit({ key: userId }),
    ]);
    if (!auth.ok && auth.reason === "signed_out") throw signedOut();
    if (!rate.success) {
      throw new ApiError(429, "rate_limited", "Too many dictations in a minute.", { "Retry-After": "60" });
    }
    if (!underCap) throw new ApiError(503, "service_paused", "kotoba Cloud is paused for today. Try again later.");
    if (!auth.ok) throw new ApiError(402, "out_of_hours", "Out of kotoba Cloud hours.");
    before = auth.balance;
  } catch (error) {
    abort.abort();
    c.executionCtx.waitUntil(balance.release(requestId));
    throw error;
  }

  let transcript: Awaited<typeof upstream>;
  try {
    transcript = await upstream;
  } catch (error) {
    c.executionCtx.waitUntil(balance.release(requestId));
    throw upstreamFailure(error, signal, audio.tooLarge(), maxBytes);
  }

  // Azure's own duration is what the user pays; a whole second at least, rounded up.
  const billed = Math.max(1, Math.ceil((transcript.durationMs ?? audioSeconds * 1000) / 1000));
  c.executionCtx.waitUntil(
    balance.settle(requestId, billed, now).then((after) => {
      // No audio and no text in logs: user, seconds and outcome only.
      console.log(JSON.stringify({ event: "transcribe", user: userId, billed, seconds_left: after.secondsLeft }));
    }),
  );
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

/** The body again, `head` first, failing once it passes `maxBytes`, so a client cannot send more than it declared. */
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
