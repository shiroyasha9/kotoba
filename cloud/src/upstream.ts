/**
 * The speech-to-text service behind the relay. `AzureTranscriber` calls MAI-Transcribe-2 on the owner's Azure Speech
 * resource (fast transcription). `FakeTranscriber` answers from the Worker, for dev, tests and the latency bench.
 * The model is fixed here: no client can pick a costlier one.
 */
export interface TranscribeInput {
  /** The client's FLAC bytes, streamed through without a copy. */
  audio: ReadableStream<Uint8Array>;
  /** Byte length from the client's Content-Length, when it sent one. */
  length: number | undefined;
  /** A language code such as "en"; undefined lets the model detect it. */
  language: string | undefined;
  /** Dictionary terms for the phrase list. */
  phrases: string[];
  /** The best known audio length before the upstream answers (the FLAC header, else the client's header). */
  audioSeconds: number;
}

export interface Transcript {
  text: string;
  /** Audio length as the upstream measured it: what the user pays for. */
  durationMs: number | undefined;
}

export interface Transcriber {
  transcribe(input: TranscribeInput, signal: AbortSignal): Promise<Transcript>;
}

export class UpstreamError extends Error {
  constructor(
    readonly kind: "busy" | "bad_audio" | "failed",
    message: string,
    readonly retryAfter?: string,
  ) {
    super(message);
  }
}

export const AZURE_API_VERSION = "2025-10-15";
export const AZURE_MODEL = "MAI-Transcribe-2";
export const AZURE_TRANSCRIBE_PATH = "/speechtotext/transcriptions:transcribe";

interface AzureSuccess {
  durationMilliseconds?: number;
  combinedPhrases?: { text: string }[];
}

interface AzureError {
  error?: { code?: string; message?: string; innerError?: { code?: string } };
  code?: string;
  innerError?: { code?: string };
}

/** Azure inner error codes that mean the audio itself is wrong, so a retry cannot help. */
const BAD_AUDIO_CODES = new Set([
  "InvalidAudioFormat",
  "EmptyAudioFile",
  "AudioLengthLimitExceeded",
  "UnsupportedMediaType",
]);

/**
 * `POST {endpoint}/speechtotext/transcriptions:transcribe`, multipart: a `definition` JSON part, then the `audio`
 * part. The body is a stream: Azure starts to receive the audio while the client still sends it.
 * API: https://learn.microsoft.com/en-us/rest/api/speechtotext/transcriptions/transcribe (2025-10-15) and
 * https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
 */
export class AzureTranscriber implements Transcriber {
  private readonly url: string;

  constructor(
    endpoint: string,
    private readonly key: string,
    // A closure, not `fetch` itself: workerd throws "Illegal invocation" when fetch runs with another `this`.
    private readonly fetcher: typeof fetch = (input, init) => fetch(input, init),
  ) {
    this.url = `${endpoint.replace(/\/+$/, "")}${AZURE_TRANSCRIBE_PATH}?api-version=${AZURE_API_VERSION}`;
  }

  async transcribe(input: TranscribeInput, signal: AbortSignal): Promise<Transcript> {
    const boundary = `kotoba-${crypto.randomUUID()}`;
    const definition = JSON.stringify({
      enhancedMode: { enabled: true, model: AZURE_MODEL },
      locales: input.language ? [input.language] : undefined,
      phraseList: input.phrases.length > 0 ? { phrases: input.phrases } : undefined,
    });
    const encoder = new TextEncoder();
    const head = encoder.encode(
      `--${boundary}\r\nContent-Disposition: form-data; name="definition"\r\nContent-Type: application/json\r\n\r\n` +
        `${definition}\r\n--${boundary}\r\nContent-Disposition: form-data; name="audio"; filename="audio.flac"\r\n` +
        "Content-Type: audio/flac\r\n\r\n",
    );
    const tail = encoder.encode(`\r\n--${boundary}--\r\n`);
    // With a known length the upstream request carries Content-Length, not chunked encoding.
    const { readable, writable } =
      input.length === undefined
        ? new IdentityTransformStream()
        : new FixedLengthStream(head.byteLength + input.length + tail.byteLength);
    const pump = writeMultipart(writable, head, input.audio, tail);
    pump.catch(() => {}); // The fetch below fails with the same cause.

    let response: Response;
    try {
      response = await this.fetcher(this.url, {
        method: "POST",
        headers: {
          "Ocp-Apim-Subscription-Key": this.key,
          "Content-Type": `multipart/form-data; boundary=${boundary}`,
        },
        body: readable,
        signal,
      });
    } catch (cause) {
      if (signal.aborted) throw cause;
      throw new UpstreamError("failed", `Azure request failed: ${String(cause)}`);
    }
    if (response.ok) {
      const body = await response.json<AzureSuccess>().catch(() => undefined);
      if (!body) throw new UpstreamError("failed", `Azure ${response.status} with a body that is not JSON`);
      return { text: body.combinedPhrases?.[0]?.text ?? "", durationMs: body.durationMilliseconds };
    }
    const error = await response.json<AzureError>().catch(() => undefined);
    const code = error?.error?.code ?? error?.code ?? "";
    const inner = error?.error?.innerError?.code ?? error?.innerError?.code ?? "";
    const detail = `Azure ${response.status} ${code}${inner ? `/${inner}` : ""}`;
    if (response.status === 429 || response.status === 503) {
      throw new UpstreamError("busy", detail, response.headers.get("Retry-After") ?? undefined);
    }
    if (BAD_AUDIO_CODES.has(inner) || BAD_AUDIO_CODES.has(code)) throw new UpstreamError("bad_audio", detail);
    throw new UpstreamError("failed", detail);
  }
}

async function writeMultipart(
  writable: WritableStream<Uint8Array>,
  head: Uint8Array,
  audio: ReadableStream<Uint8Array>,
  tail: Uint8Array,
): Promise<void> {
  let writer = writable.getWriter();
  await writer.write(head);
  writer.releaseLock();
  await audio.pipeTo(writable, { preventClose: true });
  writer = writable.getWriter();
  await writer.write(tail);
  await writer.close();
}

/** Reads the whole audio stream (so byte limits apply as in production), waits `delayMs`, and answers. */
export class FakeTranscriber implements Transcriber {
  constructor(private readonly delayMs = 0) {}

  async transcribe(input: TranscribeInput, signal: AbortSignal): Promise<Transcript> {
    let bytes = 0;
    for await (const chunk of input.audio) bytes += chunk.byteLength;
    if (this.delayMs > 0) await scheduler.wait(this.delayMs, { signal });
    signal.throwIfAborted();
    return {
      text: `Fake transcript of ${bytes} bytes.`,
      durationMs: Math.round(input.audioSeconds * 1000),
    };
  }
}
