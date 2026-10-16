import { Hono } from "hono";
import type { AppEnv } from "./app";
import { ApiError, numberVar } from "./errors";
import { hashCode, hex, SESSION_DAYS, sealSession } from "./session";

/** Sends the six-digit sign-in code. The prototype prints it; a real mailer (Resend in the proposal) comes later. */
export interface Mailer {
  sendCode(email: string, code: string): Promise<void>;
}

export class ConsoleMailer implements Mailer {
  async sendCode(email: string, code: string): Promise<void> {
    console.log(`sign-in code for ${email}: ${code}`);
  }
}

export const CODE_TTL_MS = 10 * 60 * 1000;
export const CODE_ATTEMPTS = 5;
/** A new code for the same email at most this often. */
export const RESEND_MS = 30 * 1000;

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const authRoutes = new Hono<AppEnv>();

/**
 * `{email}` -> 202. The reply is the same whether the email has an account or not. A new code replaces the old one at
 * most every RESEND_MS and keeps its count of wrong tries, so asking again does not buy more guesses.
 */
authRoutes.post("/start", async (c) => {
  await limitByClient(c.env, c.req.raw);
  const email = await readEmail(c.req.raw);
  const now = c.var.deps.now();
  const db = c.env.DB;
  const code = randomCode();
  const [, sent] = await db.batch([
    db.prepare("DELETE FROM auth_codes WHERE expires_at <= ?").bind(now),
    db
      .prepare(
        `INSERT INTO auth_codes (email, code_hash, expires_at, attempts, sent_at) VALUES (?1, ?2, ?3, 0, ?4)
         ON CONFLICT (email) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at,
           sent_at = excluded.sent_at
         WHERE auth_codes.sent_at <= ?5 AND auth_codes.attempts < ?6
         RETURNING email`,
      )
      .bind(
        email,
        await hashCode(c.env.SESSION_KEY, email, code),
        now + CODE_TTL_MS,
        now,
        now - RESEND_MS,
        CODE_ATTEMPTS,
      ),
  ]);
  if (sent?.results.length === 0) throw await refusal(db, email, now);
  await c.var.deps.mailer(c.env).sendCode(email, code);
  return c.json({ ok: true }, 202);
});

/** Why `/start` sent no code: too soon after the last one, or too many wrong tries on the live code. */
async function refusal(db: D1Database, email: string, now: number): Promise<ApiError> {
  const row = await db
    .prepare("SELECT sent_at, expires_at, attempts FROM auth_codes WHERE email = ?")
    .bind(email)
    .first<{ sent_at: number; expires_at: number; attempts: number }>();
  const locked = row !== null && row.attempts >= CODE_ATTEMPTS;
  const until = row === null ? now : locked ? row.expires_at : row.sent_at + RESEND_MS;
  const wait = Math.max(1, Math.ceil((until - now) / 1000));
  const message = locked
    ? "Too many wrong codes. Ask for a new one later."
    : "Wait a moment before you ask for a new code.";
  return new ApiError(429, "rate_limited", message, { "Retry-After": String(wait) });
}

/** `{email, code}` -> `{token, user, trial_granted}`. Makes the account on first sign-in and grants the free hour once. */
authRoutes.post("/verify", async (c) => {
  await limitByClient(c.env, c.req.raw);
  const body = await readJson<{ email?: unknown; code?: unknown }>(c.req.raw);
  const email = normalizeEmail(body.email);
  const code = typeof body.code === "string" ? body.code.trim() : "";
  if (!/^\d{6}$/.test(code)) throw new ApiError(400, "code_invalid", "The code has six digits.");
  const now = c.var.deps.now();
  const db = c.env.DB;
  // Counting the try and reading the hash is one statement, so parallel guesses cannot pass the limit.
  const [given, row] = await Promise.all([
    hashCode(c.env.SESSION_KEY, email, code),
    db
      .prepare(
        `UPDATE auth_codes SET attempts = attempts + 1 WHERE email = ? AND expires_at > ? AND attempts < ?
         RETURNING code_hash`,
      )
      .bind(email, now, CODE_ATTEMPTS)
      .first<{ code_hash: string }>(),
  ]);
  if (!row) throw new ApiError(400, "code_expired", "This code expired. Ask for a new one.");
  if (!safeEqual(given, row.code_hash)) throw new ApiError(400, "code_invalid", "That code is not right.");

  const newId = `u_${hex(crypto.getRandomValues(new Uint8Array(12)))}`;
  const [, upsert] = await db.batch([
    db.prepare("DELETE FROM auth_codes WHERE email = ?").bind(email),
    db
      .prepare(
        `INSERT INTO users (id, email, created_at) VALUES (?, ?, ?)
         ON CONFLICT (email) DO UPDATE SET email = excluded.email RETURNING id`,
      )
      .bind(newId, email, now),
  ]);
  const userId = (upsert?.results[0] as { id: string } | undefined)?.id;
  if (!userId) throw new Error("user upsert returned no row");
  // The Balance object grants the trial once (ledger ref "trial"); the D1 column is for reports.
  const { generation, trialGranted } = await c.env.BALANCE.getByName(userId).signIn(
    numberVar(c.env, "TRIAL_SECONDS"),
    now,
  );
  if (trialGranted) {
    c.executionCtx.waitUntil(db.prepare("UPDATE users SET trial_granted_at = ? WHERE id = ?").bind(now, userId).run());
  }
  const expiresAt = Math.floor(now / 1000) + SESSION_DAYS * 86_400;
  const token = await sealSession(c.env.SESSION_KEY, { userId, generation, expiresAt });
  return c.json({
    token,
    expires_at: new Date(expiresAt * 1000).toISOString(),
    user: { id: userId, email },
    trial_granted: trialGranted,
  });
});

/** Constant-time compare of two hex digests. */
function safeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  return left.byteLength === right.byteLength && crypto.subtle.timingSafeEqual(left, right);
}

async function limitByClient(env: Env, request: Request): Promise<void> {
  const key = request.headers.get("CF-Connecting-IP") ?? "local";
  const { success } = await env.AUTH_LIMITER.limit({ key });
  if (!success) {
    throw new ApiError(429, "rate_limited", "Too many sign-in tries. Wait a minute.", { "Retry-After": "60" });
  }
}

async function readEmail(request: Request): Promise<string> {
  const body = await readJson<{ email?: unknown }>(request);
  return normalizeEmail(body.email);
}

function normalizeEmail(value: unknown): string {
  const email = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (email.length > 254 || !EMAIL.test(email)) {
    throw new ApiError(400, "invalid_email", "Type a full email address.");
  }
  return email;
}

export async function readJson<T>(request: Request): Promise<T> {
  try {
    const body = await request.json<T>();
    if (body && typeof body === "object") return body;
  } catch {}
  throw new ApiError(400, "bad_request", "The body must be a JSON object.");
}

/** A uniform six-digit code (rejection sampling, so no digit string is likelier than another). */
function randomCode(): string {
  const buffer = new Uint32Array(1);
  const limit = 4_294_000_000; // The largest multiple of 1,000,000 below 2^32.
  for (;;) {
    crypto.getRandomValues(buffer);
    const value = buffer[0] ?? limit;
    if (value < limit) return String(value % 1_000_000).padStart(6, "0");
  }
}
