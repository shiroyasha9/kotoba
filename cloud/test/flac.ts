/**
 * A FLAC file head that says `seconds` of 16 kHz mono 16-bit audio (0 leaves the sample count unknown, as a streaming
 * encoder may), then `filler` bytes standing for the frames. Enough for the relay; nothing decodes it. No Workers
 * imports, so the Bun latency script uses it too.
 */
export function flac(seconds: number, filler = 2048): Uint8Array {
  const out = new Uint8Array(42 + filler);
  out.set([0x66, 0x4c, 0x61, 0x43, 0x80, 0, 0, 34]);
  const rate = 16_000;
  const samples = Math.round(seconds * rate);
  out[18] = (rate >> 12) & 0xff;
  out[19] = (rate >> 4) & 0xff;
  out[20] = (rate & 0x0f) << 4; // mono
  out[21] = (15 << 4) | Math.floor(samples / 2 ** 32); // 16 bits per sample
  out[22] = (samples >>> 24) & 0xff;
  out[23] = (samples >>> 16) & 0xff;
  out[24] = (samples >>> 8) & 0xff;
  out[25] = samples & 0xff;
  for (let i = 42; i < out.length; i++) out[i] = (i * 31) & 0xff;
  return out;
}
