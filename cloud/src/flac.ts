/** "fLaC", the STREAMINFO block header and the 34-byte STREAMINFO block. */
export const FLAC_HEAD_BYTES = 42;

/**
 * The audio length from the FLAC STREAMINFO block at the start of a file: undefined when the bytes are not FLAC
 * (`isFlac` false) or when the encoder left the sample count at 0, as a streaming encoder may.
 * Format: https://www.rfc-editor.org/rfc/rfc9639
 */
export function readStreamInfo(head: Uint8Array): { isFlac: boolean; seconds: number | undefined } {
  const b = (i: number) => head[i] ?? 0;
  const isFlac =
    head.byteLength >= FLAC_HEAD_BYTES &&
    b(0) === 0x66 &&
    b(1) === 0x4c &&
    b(2) === 0x61 &&
    b(3) === 0x43 &&
    (b(4) & 0x7f) === 0; // The first metadata block is STREAMINFO.
  if (!isFlac) return { isFlac, seconds: undefined };
  const sampleRate = (b(18) << 12) | (b(19) << 4) | (b(20) >> 4);
  const totalSamples = (b(21) & 0x0f) * 2 ** 32 + ((b(22) << 24) >>> 0) + (b(23) << 16) + (b(24) << 8) + b(25);
  return { isFlac, seconds: sampleRate && totalSamples ? totalSamples / sampleRate : undefined };
}
