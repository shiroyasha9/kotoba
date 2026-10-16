import { createMiddleware } from "hono/factory";
import { decodeBase64, decodeBase64Url, encodeBase64Url } from "hono/utils/encode";
import type { AppEnv } from "./app";
import { signedOut } from "./errors";

/**
 * Session tokens are opaque to the app: `v1.` + base64url(iv || AES-GCM ciphertext) of `{u, g, e}`. The Worker opens
 * one with no storage read. `g` is the user's session generation; the user's Balance object rejects an old one, so
 * "Sign out everywhere" (a new generation) ends every token on the next request, at no extra hop.
 */
export interface Session {
  userId: string;
  generation: number;
  /** Unix seconds. */
  expiresAt: number;
}

export const SESSION_DAYS = 180;
/** A token older than this gets a fresh one in `X-Kotoba-Token` on its next successful request (a sliding session). */
export const RENEW_AFTER_DAYS = 30;
const PREFIX = "v1.";
const AAD = new TextEncoder().encode("kotoba-session-v1");

interface Keys {
  seal: CryptoKey;
  code: CryptoKey;
}

// One import per isolate: the secret does not change while the isolate lives.
let cached: { secret: string; keys: Promise<Keys> } | undefined;

/** Two keys from the one `SESSION_KEY` secret (HKDF), so no key serves two algorithms. */
export function keys(secret: string): Promise<Keys> {
  if (cached?.secret !== secret) cached = { secret, keys: deriveKeys(secret) };
  return cached.keys;
}

async function deriveKeys(secret: string): Promise<Keys> {
  const raw = decodeBase64(secret);
  if (raw.byteLength < 32) throw new Error("SESSION_KEY must be at least 32 bytes, base64");
  const master = await crypto.subtle.importKey("raw", raw, "HKDF", false, ["deriveKey"]);
  const hkdf = (info: string) => ({
    name: "HKDF",
    hash: "SHA-256",
    salt: new Uint8Array(),
    info: new TextEncoder().encode(info),
  });
  const [seal, code] = await Promise.all([
    crypto.subtle.deriveKey(hkdf("session"), master, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]),
    crypto.subtle.deriveKey(hkdf("sign-in code"), master, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]),
  ]);
  return { seal, code };
}

export async function sealSession(secret: string, session: Session): Promise<string> {
  const { seal } = await keys(secret);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = new TextEncoder().encode(
    JSON.stringify({ u: session.userId, g: session.generation, e: session.expiresAt }),
  );
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: AAD }, seal, plain));
  const out = new Uint8Array(iv.length + sealed.length);
  out.set(iv);
  out.set(sealed, iv.length);
  return PREFIX + encodeBase64Url(out.buffer).replace(/=+$/, "");
}

/** The session in `token`, or undefined when it is forged, damaged or expired at `nowMs`. */
export async function openSession(secret: string, token: string, nowMs: number): Promise<Session | undefined> {
  if (!token.startsWith(PREFIX)) return undefined;
  let bytes: Uint8Array;
  try {
    bytes = decodeBase64Url(token.slice(PREFIX.length));
  } catch {
    return undefined;
  }
  if (bytes.length < 12 + 16) return undefined;
  const { seal } = await keys(secret);
  let plain: ArrayBuffer;
  try {
    plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: bytes.subarray(0, 12), additionalData: AAD },
      seal,
      bytes.subarray(12),
    );
  } catch {
    return undefined;
  }
  const body = JSON.parse(new TextDecoder().decode(plain)) as { u: string; g: number; e: number };
  if (body.e * 1000 <= nowMs) return undefined;
  return { userId: body.u, generation: body.g, expiresAt: body.e };
}

/** HMAC of a sign-in code for one email, hex. The table never holds a code in the clear. */
export async function hashCode(secret: string, email: string, code: string): Promise<string> {
  const { code: key } = await keys(secret);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${email}:${code}`));
  return hex(new Uint8Array(mac));
}

/** A new token for the same user and generation, valid SESSION_DAYS from `nowMs`. */
export function issueSession(secret: string, userId: string, generation: number, nowMs: number) {
  const expiresAt = Math.floor(nowMs / 1000) + SESSION_DAYS * 86_400;
  return sealSession(secret, { userId, generation, expiresAt }).then((token) => ({ token, expiresAt }));
}

/**
 * `Authorization: Bearer <token>` -> `c.var.session`, or 401 `signed_out`. A 200 answer to a token older than
 * RENEW_AFTER_DAYS carries a fresh one in `X-Kotoba-Token` (expiry in `X-Kotoba-Token-Expires`); the app stores it.
 * Only a 200 renews: there the user's Balance object has already accepted the token's generation.
 */
export const requireSession = createMiddleware<AppEnv>(async (c, next) => {
  const header = c.req.header("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  const now = c.var.deps.now();
  const session = token ? await openSession(c.env.SESSION_KEY, token, now) : undefined;
  if (!session) throw signedOut();
  c.set("session", session);
  await next();
  const issuedAt = (session.expiresAt - SESSION_DAYS * 86_400) * 1000;
  if (c.res.status !== 200 || now - issuedAt < RENEW_AFTER_DAYS * 86_400_000) return;
  const renewed = await issueSession(c.env.SESSION_KEY, session.userId, session.generation, now);
  c.header("X-Kotoba-Token", renewed.token);
  c.header("X-Kotoba-Token-Expires", new Date(renewed.expiresAt * 1000).toISOString());
});

export function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** The bytes of a hex string, or undefined when it is not hex. */
export function decodeHex(text: string): Uint8Array | undefined {
  if (text.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(text)) return undefined;
  return Uint8Array.from({ length: text.length / 2 }, (_, i) => Number.parseInt(text.slice(i * 2, i * 2 + 2), 16));
}
