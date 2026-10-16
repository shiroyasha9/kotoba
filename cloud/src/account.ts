import { Hono } from "hono";
import type { AppEnv } from "./app";
import { type AudioLimits, audioLimits, type BalanceSnapshot, coveredBytes } from "./balance";
import { signedOut } from "./errors";
import { requireSession } from "./session";

export const accountRoutes = new Hono<AppEnv>();

/** Plan and hours left. The app asks at sign-in and when it becomes active after a checkout; never on a timer. */
accountRoutes.get("/account", requireSession, async (c) => {
  const { userId, generation } = c.var.session;
  const [user, reply] = await Promise.all([
    c.env.DB.prepare("SELECT email FROM users WHERE id = ?").bind(userId).first<{ email: string }>(),
    c.env.BALANCE.getByName(userId).account(generation, c.var.deps.now()),
  ]);
  if (!user || !reply.ok) throw signedOut();
  return c.json({ user: { id: userId, email: user.email }, ...balanceJson(reply.balance, audioLimits(c.env)) });
});

/** Ends every token of this user, this one too. A token that is already ended gets 401. */
accountRoutes.post("/sign-out-everywhere", requireSession, async (c) => {
  const { userId, generation } = c.var.session;
  if (!(await c.env.BALANCE.getByName(userId).signOutEverywhere(generation))) throw signedOut();
  return c.body(null, 204);
});

/**
 * The balance as the API shows it: seconds, ISO times or null, and `covered_bytes`, the largest recording the balance
 * covers now. The app checks a recording against it while it records and before it uploads, so "not enough hours"
 * comes before the upload, not after. Holds of dictations still in flight are not subtracted.
 */
export function balanceJson(balance: BalanceSnapshot, limits: AudioLimits) {
  const iso = (ms: number) => (ms === 0 ? null : new Date(ms).toISOString());
  return {
    plan: balance.planPeriodEnd === 0 ? null : "pro",
    seconds_left: balance.secondsLeft,
    plan_seconds_left: balance.planSecondsLeft,
    pack_seconds: balance.packSeconds,
    plan_period_end: iso(balance.planPeriodEnd),
    plan_resets_at: iso(balance.planResetsAt),
    covered_bytes: coveredBytes(balance.secondsLeft, limits),
  };
}
