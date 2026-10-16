import { Hono } from "hono";
import type { AppEnv } from "./app";
import { ApiError, numberVar } from "./errors";
import { decodeHex } from "./session";

/**
 * Paddle Billing notifications (Paddle is the Merchant of Record; it holds cards, tax and refunds). The checkout passes
 * `custom_data: {"kotoba_user_id": "<id>"}`; Paddle copies it to the transaction and to the subscription.
 * - `transaction.completed`: a pack adds pack hours; a Pro price starts the paid period (`billing_period`), every
 *   renewal too, so renewals need no other event.
 * - `subscription.*` (created, updated, paused, resumed, canceled): kept in D1; status `canceled` or `paused` ends the
 *   plan hours now. A resume brings no hours back: the next `transaction.completed` does.
 * - `adjustment.created|updated`, an approved refund or chargeback: takes back the refunded share of a pack's or a Pro
 *   period's unused seconds, never below zero (`takeBackRefund`). Adjustments carry no `custom_data`, so the user
 *   comes from `purchases`.
 * Paddle retries a notification until it gets a 200 and does not keep the order. The `paddle_events` check only saves
 * work: the writes themselves are idempotent (the Balance ledger by transaction and price, `purchases` by key,
 * `subscriptions` by event time), so two deliveries that race both land once.
 * Docs: https://developer.paddle.com/webhooks/signature-verification, https://developer.paddle.com/webhooks/respond-to-webhooks
 */
export const paddleRoutes = new Hono<AppEnv>();

const NO_PURCHASE = "no_purchase";

interface Product {
  kind: "pack" | "pro";
  seconds: number;
}

interface Item {
  price: { id: string };
  quantity: number;
}

interface PaddleEvent {
  event_id: string;
  event_type: string;
  occurred_at: string;
  data: {
    id: string;
    status?: string;
    subscription_id?: string | null;
    custom_data?: { kotoba_user_id?: unknown } | null;
    items?: Item[];
    billing_period?: { starts_at: string; ends_at: string } | null;
    current_billing_period?: { starts_at: string; ends_at: string } | null;
    details?: { line_items?: { id: string; price_id: string; totals: { total: string } }[] };
  };
}

/** `adjustment.*` data: https://developer.paddle.com/webhooks/adjustments/adjustment-created */
interface Adjustment {
  id: string;
  action: string;
  type?: "full" | "partial";
  status: string;
  transaction_id: string;
  items: { item_id: string; type: string; amount: string | null }[];
}

paddleRoutes.post("/paddle", async (c) => {
  const raw = await c.req.text();
  const now = c.var.deps.now();
  const valid = await verifySignature(
    c.req.header("Paddle-Signature"),
    raw,
    c.env.PADDLE_WEBHOOK_SECRET,
    now,
    numberVar(c.env, "PADDLE_TOLERANCE_SECONDS"),
  );
  if (!valid) throw new ApiError(401, "bad_signature", "Signature check failed.");
  const event = JSON.parse(raw) as PaddleEvent;
  const db = c.env.DB;
  const seen = await db.prepare("SELECT 1 FROM paddle_events WHERE event_id = ?").bind(event.event_id).first();
  if (seen) return c.json({ ok: true, duplicate: true });

  const outcome = await handle(c.env, event, now);
  // Paddle does not keep the order: a refund can come before its purchase. A non-200 makes Paddle send it again later.
  if (outcome === NO_PURCHASE) return c.json({ ok: false, outcome }, 409);
  await db
    .prepare(
      "INSERT OR IGNORE INTO paddle_events (event_id, event_type, occurred_at, outcome, received_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(event.event_id, event.event_type, event.occurred_at, outcome, now)
    .run();
  console.log(JSON.stringify({ event: "paddle", type: event.event_type, id: event.event_id, outcome }));
  return c.json({ ok: true, outcome });
});

/** What the event did, for the log and the `paddle_events` row. An event we cannot place still gets a 200. */
async function handle(env: Env, event: PaddleEvent, now: number): Promise<string> {
  if (event.event_type === "adjustment.created" || event.event_type === "adjustment.updated") {
    return takeBackRefund(env, event.data as unknown as Adjustment, now);
  }
  const userId = await knownUser(env.DB, event.data.custom_data?.kotoba_user_id);
  if (!userId) return "no_user";
  switch (event.event_type) {
    case "transaction.completed":
      return completeTransaction(env, userId, event, now);
    case "subscription.created":
    case "subscription.updated":
    case "subscription.paused":
    case "subscription.resumed":
    case "subscription.canceled":
      return updateSubscription(env, userId, event, now);
    default:
      return "ignored";
  }
}

async function completeTransaction(env: Env, userId: string, event: PaddleEvent, now: number): Promise<string> {
  const prices = env.PADDLE_PRICES as unknown as Record<string, Product | undefined>;
  const txn = event.data;
  const balance = env.BALANCE.getByName(userId);
  const outcomes: string[] = [];
  for (const item of txn.items ?? []) {
    const product = prices[item.price.id];
    if (!product) {
      outcomes.push(`unknown_price:${item.price.id}`);
      continue;
    }
    const ref = `${txn.id}:${item.price.id}`;
    const line = txn.details?.line_items?.find((l) => l.price_id === item.price.id);
    let seconds = product.seconds;
    if (product.kind === "pack") {
      seconds *= item.quantity;
      await balance.addPack(ref, seconds, now);
    } else {
      const period = txn.billing_period;
      if (!period || !txn.subscription_id) {
        outcomes.push("pro_without_subscription");
        continue;
      }
      await balance.startPlan(
        ref,
        {
          subscriptionId: txn.subscription_id,
          monthlySeconds: seconds,
          periodStart: Date.parse(period.starts_at),
          periodEnd: Date.parse(period.ends_at),
        },
        now,
      );
    }
    await env.DB.prepare(
      `INSERT OR IGNORE INTO purchases
         (paddle_txn_id, price_id, line_item_id, amount_total, user_id, kind, seconds_granted, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(txn.id, item.price.id, line?.id ?? null, line?.totals.total ?? null, userId, product.kind, seconds, now)
      .run();
    outcomes.push(product.kind);
  }
  return outcomes.join(",") || "no_items";
}

async function updateSubscription(env: Env, userId: string, event: PaddleEvent, now: number): Promise<string> {
  const sub = event.data;
  const status = event.event_type === "subscription.canceled" ? "canceled" : (sub.status ?? "unknown");
  // Paddle does not keep the order: an older event than the stored one changes nothing. The same event again (a
  // retry after a failure further down) applies again.
  const result = await env.DB.prepare(
    `INSERT INTO subscriptions (paddle_sub_id, user_id, price_id, status, period_end, event_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6)
     ON CONFLICT (paddle_sub_id) DO UPDATE SET price_id = ?3, status = ?4, period_end = COALESCE(?5, period_end),
       event_at = ?6
     WHERE excluded.event_at >= subscriptions.event_at`,
  )
    .bind(
      sub.id,
      userId,
      sub.items?.[0]?.price.id ?? null,
      status,
      sub.current_billing_period ? Date.parse(sub.current_billing_period.ends_at) : null,
      Date.parse(event.occurred_at),
    )
    .run();
  if (result.meta.changes === 0) return "stale";
  if (status === "canceled" || status === "paused") {
    await env.BALANCE.getByName(userId).endPlan(sub.id, status === "canceled", now);
    return `plan_ended:${status}`;
  }
  return status;
}

interface PurchaseRow {
  user_id: string;
  price_id: string;
  line_item_id: string | null;
  amount_total: string | null;
  kind: "pack" | "pro";
  seconds_granted: number;
}

/**
 * An approved refund or chargeback takes back the refunded share (the refund's money over the line's total; all of it
 * for a full refund) of what it bought, never below zero: of a pack's seconds, from what is left of that pack
 * (`Balance.takeBackPack`); of a Pro payment, from that period's unused plan seconds, and a full refund ends the period
 * (`Balance.takeBackPlan`). A refund of a renewal leaves the subscription active, so this cannot wait for a
 * subscription event. Shares of several partial refunds add up to at most the whole, as Paddle never refunds more than
 * was paid. Tax and proration lines take nothing.
 */
async function takeBackRefund(env: Env, adjustment: Adjustment, now: number): Promise<string> {
  if (adjustment.action !== "refund" && adjustment.action !== "chargeback") return "ignored";
  if (adjustment.status !== "approved") return "not_approved";
  const { results } = await env.DB.prepare(
    `SELECT user_id, price_id, line_item_id, amount_total, kind, seconds_granted FROM purchases
     WHERE paddle_txn_id = ?`,
  )
    .bind(adjustment.transaction_id)
    .all<PurchaseRow>();
  if (results.length === 0) return NO_PURCHASE;
  const takes = adjustment.items.map((item) => {
    const purchase = results.find((row) => row.line_item_id === item.item_id);
    if (!purchase || (item.type !== "full" && item.type !== "partial")) return 0;
    const ratio =
      item.type === "full" || item.amount === null ? 1 : Number(item.amount) / Number(purchase.amount_total);
    if (!Number.isFinite(ratio)) return 0;
    const share = Math.min(1, ratio);
    const ref = `refund:${adjustment.id}:${item.item_id}`;
    const bought = `${adjustment.transaction_id}:${purchase.price_id}`;
    const balance = env.BALANCE.getByName(purchase.user_id);
    if (purchase.kind === "pro") return balance.takeBackPlan(ref, bought, share, now);
    return balance.takeBackPack(ref, bought, Math.floor(purchase.seconds_granted * share), now);
  });
  const taken = (await Promise.all(takes)).reduce((sum, seconds) => sum + seconds, 0);
  return `refund:${taken}`;
}

async function knownUser(db: D1Database, value: unknown): Promise<string | undefined> {
  if (typeof value !== "string") return undefined;
  const row = await db.prepare("SELECT id FROM users WHERE id = ?").bind(value).first<{ id: string }>();
  return row?.id;
}

/**
 * `Paddle-Signature: ts=<unix seconds>;h1=<hex>[;h1=<hex>]`: h1 is HMAC-SHA256 of `<ts>:<raw body>` with the
 * notification destination's secret. During a secret rotation Paddle sends one h1 per secret; one match is enough.
 * Paddle's SDKs reject a ts older than 5 seconds, against replays. `crypto.subtle.verify` compares in constant time.
 */
export async function verifySignature(
  header: string | undefined,
  rawBody: string,
  secret: string,
  nowMs: number,
  toleranceSeconds: number,
): Promise<boolean> {
  if (!header) return false;
  let ts: string | undefined;
  const signatures: Uint8Array[] = [];
  for (const part of header.split(";")) {
    const [key, value] = part.split("=", 2).map((s) => s.trim());
    const bytes = key === "h1" && value ? decodeHex(value) : undefined;
    if (key === "ts") ts = value;
    else if (bytes) signatures.push(bytes);
  }
  if (!ts || !/^\d+$/.test(ts) || signatures.length === 0) return false;
  if (!(Math.abs(nowMs / 1000 - Number(ts)) <= toleranceSeconds)) return false;
  const key = await hmacKey(secret);
  const signed = new TextEncoder().encode(`${ts}:${rawBody}`);
  for (const signature of signatures) {
    if (await crypto.subtle.verify("HMAC", key, signature, signed)) return true;
  }
  return false;
}

// One import per isolate, as for the session keys.
let cachedKey: { secret: string; key: Promise<CryptoKey> } | undefined;

function hmacKey(secret: string): Promise<CryptoKey> {
  if (cachedKey?.secret !== secret) {
    const key = crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    cachedKey = { secret, key };
  }
  return cachedKey.key;
}
