import { describe, expect, it } from "vitest";
import { verifySignature } from "../src/paddle";
import { hex } from "../src/session";
import canceled from "./fixtures/subscription-canceled.json";
import updated from "./fixtures/subscription-updated.json";
import pack from "./fixtures/transaction-completed-pack.json";
import pro from "./fixtures/transaction-completed-pro.json";
import { account, errorCode, type Harness, harness, signIn, T0 } from "./helpers";

const SECRET = "pdl_ntfset_test_secret";

async function sign(body: string, ts: number, secret = SECRET): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${ts}:${body}`));
  return hex(new Uint8Array(mac));
}

/** The fixture as Paddle would send it, for `userId`, with a fresh event id when `eventId` is set. */
function payload(fixture: object, userId: string, eventId?: string): string {
  const body = JSON.stringify(fixture).replaceAll("{{user}}", userId);
  return eventId ? body.replace(/"event_id":"[^"]+"/, `"event_id":"${eventId}"`) : body;
}

async function deliver(h: Harness, body: string, signature?: string): Promise<Response> {
  const ts = Math.floor(h.clock.now / 1000);
  return h.fetch("/billing/paddle", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Paddle-Signature": signature ?? `ts=${ts};h1=${await sign(body, ts)}`,
    },
    body,
  });
}

describe("verifySignature", () => {
  const body = '{"event_id":"evt_1"}';
  const ts = Math.floor(T0 / 1000);

  it("accepts Paddle's signature and refuses a wrong secret, a changed body or an old timestamp", async () => {
    const h1 = await sign(body, ts);
    expect(await verifySignature(`ts=${ts};h1=${h1}`, body, SECRET, T0, 5)).toBe(true);
    expect(await verifySignature(`ts=${ts};h1=${h1}`, body, "other", T0, 5)).toBe(false);
    expect(await verifySignature(`ts=${ts};h1=${h1}`, `${body} `, SECRET, T0, 5)).toBe(false);
    expect(await verifySignature(`ts=${ts};h1=${h1}`, body, SECRET, T0 + 6000, 5)).toBe(false);
  });

  it("accepts any one matching h1 during a secret rotation", async () => {
    const header = `ts=${ts};h1=${await sign(body, ts, "old")};h1=${await sign(body, ts)}`;
    expect(await verifySignature(header, body, SECRET, T0, 5)).toBe(true);
  });

  it("refuses a missing or malformed header", async () => {
    expect(await verifySignature(undefined, body, SECRET, T0, 5)).toBe(false);
    expect(await verifySignature("h1=abc", body, SECRET, T0, 5)).toBe(false);
    expect(await verifySignature(`ts=${ts}`, body, SECRET, T0, 5)).toBe(false);
    expect(await verifySignature(`ts=${ts};h1=zz`, body, SECRET, T0, 5)).toBe(false);
  });
});

describe("POST /billing/paddle", () => {
  it("adds pack hours for each unit bought, once, however often Paddle retries", async () => {
    const h = harness();
    const { token, userId } = await signIn(h);
    const body = payload(pack, userId);
    const first = await deliver(h, body);
    expect(await first.json()).toEqual({ ok: true, outcome: "pack" });
    expect(await account(h, token)).toMatchObject({ seconds_left: 3600 + 2 * 18000 });

    expect(await (await deliver(h, body)).json()).toEqual({ ok: true, duplicate: true });
    // A new event about the same transaction does not pay twice either.
    await deliver(h, payload(pack, userId, "evt_other"));
    expect(await account(h, token)).toMatchObject({ seconds_left: 3600 + 2 * 18000 });
  });

  it("starts Pro hours from the billing period, and ends them on cancel", async () => {
    const h = harness();
    const { token, userId } = await signIn(h);
    expect(await (await deliver(h, payload(pro, userId))).json()).toEqual({ ok: true, outcome: "pro" });
    expect(await account(h, token)).toMatchObject({
      plan: "pro",
      plan_seconds_left: 28800,
      seconds_left: 28800 + 3600,
      plan_period_end: "2026-11-17T06:00:00.000Z",
    });

    // A scheduled cancel keeps the hours to the end of the period.
    expect(await (await deliver(h, payload(updated, userId))).json()).toMatchObject({ outcome: "active" });
    expect(await account(h, token)).toMatchObject({ plan: "pro" });

    expect(await (await deliver(h, payload(canceled, userId))).json()).toMatchObject({
      outcome: "plan_ended:canceled",
    });
    expect(await account(h, token)).toMatchObject({ plan: null, plan_seconds_left: 0, seconds_left: 3600 });

    // The older "updated" event, delivered late under a new id, changes nothing.
    const late = await deliver(h, payload(updated, userId, "evt_late"));
    expect(await late.json()).toMatchObject({ outcome: "stale" });
  });

  it("answers 200 for an event it cannot place, so Paddle stops retrying", async () => {
    const h = harness();
    const response = await deliver(h, payload(pack, "u_nobody", "evt_nobody"));
    expect(await response.json()).toEqual({ ok: true, outcome: "no_user" });
  });

  it("refuses a bad signature with 401, so a forged event credits nothing", async () => {
    const h = harness();
    const { token, userId } = await signIn(h);
    const response = await deliver(h, payload(pack, userId), `ts=${Math.floor(T0 / 1000)};h1=${"0".repeat(64)}`);
    expect([response.status, await errorCode(response)]).toEqual([401, "bad_signature"]);
    expect(await account(h, token)).toMatchObject({ seconds_left: 3600 });
  });
});
