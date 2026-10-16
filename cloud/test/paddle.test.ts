import { describe, expect, it } from "vitest";
import { verifySignature } from "../src/paddle";
import { hex } from "../src/session";
import refund from "./fixtures/adjustment-updated-refund.json";
import canceled from "./fixtures/subscription-canceled.json";
import updated from "./fixtures/subscription-updated.json";
import pack from "./fixtures/transaction-completed-pack.json";
import pro from "./fixtures/transaction-completed-pro.json";
import { account, dictation, errorCode, type Harness, harness, signIn, speech, T0 } from "./helpers";

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

const PACK_TXN = "txn_01kotobapack0000000000000001";
const PRO_SUB = "sub_01kotobapro00000000000000001";
const PRO_TXN = "txn_01kotobapro00000000000000001";
const PACK_ITEM = "txnitm_01kotobapack0000000000000001";
const PRO_ITEM = "txnitm_01kotobapro00000000000000001";

/**
 * The fixture as Paddle would send it, for `userId`, with a fresh event id when `eventId` is set. `renames` swaps ids
 * (transactions, subscriptions, adjustments): D1 tables are shared by the tests of this file.
 */
function payload(fixture: object, userId: string, eventId?: string, renames: Record<string, string> = {}): string {
  let body = JSON.stringify(fixture).replaceAll("{{user}}", userId);
  for (const [from, to] of Object.entries(renames)) body = body.replaceAll(from, to);
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

  it("brings plan hours back after a pause only with the next payment", async () => {
    const h = harness();
    const { token, userId } = await signIn(h);
    const own = (fixture: object, eventId: string) =>
      JSON.parse(payload(fixture, userId, eventId, { [PRO_SUB]: "sub_pause" }));
    await deliver(h, JSON.stringify(own(pro, "evt_pro_1")));
    const at = (iso: string) => JSON.stringify(updated).replaceAll("2026-11-01T06:00:00.000000Z", iso);
    const paused = own(JSON.parse(at("2026-10-20T06:00:00.000000Z")), "evt_paused");
    paused.event_type = "subscription.paused";
    paused.data.status = "paused";
    paused.data.scheduled_change = null;
    expect(await (await deliver(h, JSON.stringify(paused))).json()).toMatchObject({
      outcome: "plan_ended:paused",
    });
    const resumed = own(JSON.parse(at("2026-10-25T06:00:00.000000Z")), "evt_resumed");
    resumed.event_type = "subscription.resumed";
    resumed.data.scheduled_change = null;
    await deliver(h, JSON.stringify(resumed));
    expect(await account(h, token)).toMatchObject({ plan: null, plan_seconds_left: 0 });

    const renewal = own(pro, "evt_pro_2");
    renewal.data.id = `${PRO_TXN}-2`; // A new payment.
    renewal.data.billing_period = { starts_at: "2026-10-25T06:00:00.000000Z", ends_at: "2026-11-25T06:00:00.000000Z" };
    await deliver(h, JSON.stringify(renewal));
    expect(await account(h, token)).toMatchObject({ plan: "pro", plan_seconds_left: 28800 });
  });

  it("takes back a refunded pack's unused hours once approved, never below zero", async () => {
    const h = harness();
    const { token, userId } = await signIn(h, { trialSeconds: 0 });
    const own = (fixture: object, eventId?: string) =>
      payload(fixture, userId, eventId, { [PACK_TXN]: "txn_refund_full" });
    await deliver(h, own(pack, "evt_pack_r"));
    const pending = JSON.parse(own(refund, "evt_refund_pending"));
    pending.event_type = "adjustment.created";
    pending.data.status = "pending_approval";
    expect(await (await deliver(h, JSON.stringify(pending))).json()).toMatchObject({ outcome: "not_approved" });
    expect(await account(h, token)).toMatchObject({ pack_seconds: 36000 });

    // Some hours are used before Paddle approves the refund.
    expect((await h.fetch("/v1/transcribe", dictation(token, speech(10), 10))).status).toBe(200);
    expect(await (await deliver(h, own(refund))).json()).toMatchObject({ outcome: "refund:35990" });
    expect(await account(h, token)).toMatchObject({ pack_seconds: 0, seconds_left: 0 });
    expect(await (await deliver(h, own(refund, "evt_refund_again"))).json()).toMatchObject({
      outcome: "refund:0",
    });
  });

  it("takes back a share of the seconds for a partial refund", async () => {
    const h = harness();
    const { token, userId } = await signIn(h, { trialSeconds: 0 });
    const renames = { [PACK_TXN]: "txn_partial" };
    await deliver(h, payload(pack, userId, "evt_pack_p", renames));
    const partial = (adjustment: string, eventId: string) => {
      const body = JSON.parse(
        payload(refund, userId, eventId, { ...renames, adj_01kotobarefund000000000000001: adjustment }),
      );
      body.data.type = "partial";
      body.data.items[0].type = "partial";
      body.data.items[0].amount = "22450"; // A quarter of 89800.
      return JSON.stringify(body);
    };
    await deliver(h, partial("adj_partial_1", "evt_refund_partial_1"));
    expect(await account(h, token)).toMatchObject({ pack_seconds: 27000 });
    // A second partial refund takes another quarter, not more.
    await deliver(h, partial("adj_partial_2", "evt_refund_partial_2"));
    expect(await account(h, token)).toMatchObject({ pack_seconds: 18000 });
  });

  it("ends a refunded Pro period and takes back its unused plan seconds, with no subscription event", async () => {
    const h = harness();
    const { token, userId } = await signIn(h, { trialSeconds: 0 });
    const renames = { [PRO_TXN]: "txn_pro_refund", [PRO_SUB]: "sub_pro_refund" };
    await deliver(h, payload(pro, userId, "evt_pro_refund_txn", renames));
    expect((await h.fetch("/v1/transcribe", dictation(token, speech(10), 10))).status).toBe(200);
    const body = JSON.parse(
      payload(refund, userId, "evt_pro_refund", {
        ...renames,
        [PACK_TXN]: "txn_pro_refund",
        [PACK_ITEM]: PRO_ITEM,
        adj_01kotobarefund000000000000001: "adj_pro_refund",
      }),
    );
    body.data.subscription_id = "sub_pro_refund";
    body.data.items[0].amount = "400";
    expect(await (await deliver(h, JSON.stringify(body))).json()).toMatchObject({ outcome: "refund:28790" });
    expect(await account(h, token)).toMatchObject({ plan: null, plan_seconds_left: 0, seconds_left: 0 });
  });

  it("asks Paddle to send a refund again when it comes before its purchase", async () => {
    const h = harness();
    const { token, userId } = await signIn(h, { trialSeconds: 0 });
    const renames = { [PACK_TXN]: "txn_early" };
    const early = await deliver(h, payload(refund, userId, "evt_early", renames));
    expect([early.status, await early.json()]).toEqual([409, { ok: false, outcome: "no_purchase" }]);
    await deliver(h, payload(pack, userId, "evt_early_pack", renames));
    expect(await (await deliver(h, payload(refund, userId, "evt_early", renames))).json()).toMatchObject({
      outcome: "refund:36000",
    });
    expect(await account(h, token)).toMatchObject({ pack_seconds: 0 });
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
