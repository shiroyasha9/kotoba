import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { type Deps, makeApp } from "../src/app";
import type { Mailer } from "../src/auth";
import { FakeTranscriber, type Transcriber } from "../src/upstream";

export const T0 = Date.UTC(2026, 9, 17, 6, 0, 0);

/** Codes the app "sent", by email. */
export class CapturingMailer implements Mailer {
  readonly codes = new Map<string, string>();
  async sendCode(email: string, code: string): Promise<void> {
    this.codes.set(email, code);
  }
}

export interface Harness {
  /** Sends a request through the app and waits for its `waitUntil` work (the payment), like a finished request. */
  fetch(path: string, init?: RequestInit, overrides?: Partial<Env>): Promise<Response>;
  mailer: CapturingMailer;
  clock: { now: number };
}

export function harness(transcriber: (env: Env) => Transcriber = () => new FakeTranscriber()): Harness {
  const mailer = new CapturingMailer();
  const clock = { now: T0 };
  const deps: Deps = { now: () => clock.now, transcriber, mailer: () => mailer };
  const app = makeApp(deps);
  return {
    mailer,
    clock,
    async fetch(path, init, overrides) {
      const ctx = createExecutionContext();
      const response = await app.fetch(new Request(`https://cloud.test${path}`, init), { ...env, ...overrides }, ctx);
      await waitOnExecutionContext(ctx);
      return response;
    },
  };
}

let emails = 0;
/** A new email each call: storage is shared by the tests of one file. */
export function newEmail(): string {
  emails += 1;
  return `user${emails}-${crypto.randomUUID().slice(0, 8)}@example.com`;
}

export async function signIn(h: Harness, email = newEmail()): Promise<{ token: string; userId: string }> {
  const ip = `198.51.100.${(emails % 250) + 1}-${email}`;
  const start = await h.fetch("/auth/start", json({ email }, ip));
  if (start.status !== 202) throw new Error(`auth/start ${start.status}: ${await start.text()}`);
  const verify = await h.fetch("/auth/verify", json({ email, code: h.mailer.codes.get(email) }, ip));
  const body = await verify.json<{ token: string; user: { id: string } }>();
  return { token: body.token, userId: body.user.id };
}

/** A JSON POST from client `ip` (sign-in tries are limited per client IP). */
export function json(body: unknown, ip = "203.0.113.1"): RequestInit {
  return {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify(body),
  };
}

export { flac } from "./flac";

export function bearer(token: string): RequestInit {
  return { headers: { Authorization: `Bearer ${token}` } };
}

/** GET /v1/account as JSON; fails the test on any status but 200. */
export async function account(h: Harness, token: string): Promise<Record<string, unknown>> {
  const response = await h.fetch("/v1/account", bearer(token));
  if (response.status !== 200) throw new Error(`account ${response.status}: ${await response.text()}`);
  return response.json();
}

export function dictation(token: string, audio: Uint8Array, seconds: number, headers: Record<string, string> = {}) {
  return {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "audio/flac",
      "X-Kotoba-Audio-Seconds": String(seconds),
      ...headers,
    },
    body: audio,
  } satisfies RequestInit;
}

export async function errorCode(response: Response): Promise<string | undefined> {
  const body = await response.json<{ error?: { code: string } }>();
  return body.error?.code;
}
