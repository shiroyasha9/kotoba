/** "fLaC", the STREAMINFO block header and the 34-byte STREAMINFO block. */
export const FLAC_HEAD_BYTES = 42;

/** What the app records (`App/CaptureWriter.swift`): 16 kHz mono 16-bit. */
export const APP_FORMAT = { sampleRate: 16_000, channels: 1, bitsPerSample: 16 } as const;

export interface StreamInfo {
  isFlac: boolean;
  sampleRate: number;
  channels: number;
  bitsPerSample: number;
  /** Undefined for bytes that are not FLAC, or when the encoder left the sample count at 0 (a streaming encoder may). */
  seconds: number | undefined;
}

/**
 * The STREAMINFO block at the start of a FLAC file. Every field is the file's own claim: fit to refuse a file, never
 * to price one. Format: https://www.rfc-editor.org/rfc/rfc9639
 */
export function readStreamInfo(head: Uint8Array): StreamInfo {
  const b = (i: number) => head[i] ?? 0;
  const isFlac =
    head.byteLength >= FLAC_HEAD_BYTES &&
    b(0) === 0x66 &&
    b(1) === 0x4c &&
    b(2) === 0x61 &&
    b(3) === 0x43 &&
    (b(4) & 0x7f) === 0; // The first metadata block is STREAMINFO.
  const sampleRate = (b(18) << 12) | (b(19) << 4) | (b(20) >> 4);
  const channels = ((b(20) >> 1) & 0x07) + 1;
  const bitsPerSample = (((b(20) & 0x01) << 4) | (b(21) >> 4)) + 1;
  const totalSamples = (b(21) & 0x0f) * 2 ** 32 + ((b(22) << 24) >>> 0) + (b(23) << 16) + (b(24) << 8) + b(25);
  const seconds = isFlac && sampleRate && totalSamples ? totalSamples / sampleRate : undefined;
  return { isFlac, sampleRate, channels, bitsPerSample, seconds };
}

export function isAppFormat(info: StreamInfo): boolean {
  return (
    info.isFlac &&
    info.sampleRate === APP_FORMAT.sampleRate &&
    info.channels === APP_FORMAT.channels &&
    info.bitsPerSample === APP_FORMAT.bitsPerSample
  );
}
