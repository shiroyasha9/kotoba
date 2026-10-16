import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { HOLD_MS, windowEnd } from "../src/balance";
import { DAY, T0 } from "./helpers";

const HOUR = 3600;

function balance() {
  return env.BALANCE.getByName(`u_${crypto.randomUUID()}`);
}

describe("Balance", () => {
  it("spends plan hours before pack hours", async () => {
    const b = balance();
    await b.addPack("txn_1:pri_pack_5h", 5 * HOUR, T0);
    await b.startPlan(
      "txn_2:pri_pro_monthly",
      { subscriptionId: "sub_1", monthlySeconds: 100, periodStart: T0, periodEnd: T0 + 30 * DAY },
      T0,
    );
    expect(await b.authorize("r1", 150, 150, 0, T0)).toMatchObject({
      ok: true,
      balance: { secondsLeft: 5 * HOUR + 100 },
    });
    const after = await b.settle("r1", 150, T0);
    expect(after).toMatchObject({ planSecondsLeft: 0, packSeconds: 5 * HOUR - 50 });
  });

  it("settles a request once", async () => {
    const b = balance();
    await b.addPack("p", 100, T0);
    await b.settle("r1", 10, T0);
    expect(await b.settle("r1", 10, T0)).toMatchObject({ secondsLeft: 90 });
  });

  it("credits a pack once per ref", async () => {
    const b = balance();
    expect(await b.addPack("txn_1:pri_pack_5h", 100, T0)).toBe(true);
    expect(await b.addPack("txn_1:pri_pack_5h", 100, T0)).toBe(false);
    expect(await b.account(0, T0)).toMatchObject({ ok: true, balance: { packSeconds: 100 } });
  });

  it("starts a dictation when the free seconds cover its stated length, and holds at most the free seconds", async () => {
    const b = balance();
    await b.addPack("p", 30, T0);
    expect(await b.authorize("r0", 31, 100, 0, T0)).toEqual({ ok: false, reason: "not_enough_hours" });
    // The byte bound (100) is more than the balance: the hold is the 30 s that are free.
    expect(await b.authorize("r1", 10, 100, 0, T0)).toMatchObject({ ok: true, hold: 30 });
    // Seconds are left, but all are held.
    expect(await b.authorize("r2", 1, 5, 0, T0)).toEqual({ ok: false, reason: "not_enough_hours" });
    await b.release("r1");
    expect(await b.authorize("r3", 10, 25, 0, T0)).toMatchObject({ ok: true, hold: 25 });
    expect(await b.authorize("r4", 5, 5, 0, T0)).toMatchObject({ ok: true, hold: 5 });
    // An unsettled hold lapses.
    expect(await b.authorize("r5", 30, 30, 0, T0 + HOLD_MS)).toMatchObject({ ok: true, hold: 30 });
  });

  it("cuts a hold to the free seconds only when no other dictation is open", async () => {
    const b = balance();
    await b.addPack("p", 30, T0);
    expect(await b.authorize("r1", 1, 29, 0, T0)).toMatchObject({ ok: true, hold: 29 });
    // One second is free, but a second dictation with a short claim could get far more text than it pays for.
    expect(await b.authorize("r2", 1, 1200, 0, T0)).toEqual({ ok: false, reason: "not_enough_hours" });
    expect(await b.authorize("r3", 1, 1, 0, T0)).toMatchObject({ ok: true, hold: 1 });
  });

  it("settles at most the hold", async () => {
    const b = balance();
    await b.addPack("p", 100, T0);
    await b.authorize("r1", 10, 10, 0, T0);
    expect(await b.settle("r1", 50, T0)).toMatchObject({ secondsLeft: 90 });
  });

  it("takes back only what is left of the refunded pack, once, never below zero", async () => {
    const b = balance();
    await b.addPack("txn_a:pri_pack_5h", 100, T0);
    await b.authorize("r1", 70, 70, 0, T0);
    await b.settle("r1", 70, T0);
    await b.addPack("txn_b:pri_pack_5h", 100, T0 + 1);
    // Pack A has 30 left; pack B is untouched.
    expect(await b.takeBackPack("refund:adj_1:txnitm_a", "txn_a:pri_pack_5h", 100, T0)).toBe(30);
    expect(await b.takeBackPack("refund:adj_1:txnitm_a", "txn_a:pri_pack_5h", 100, T0)).toBe(0);
    expect(await b.account(0, T0)).toMatchObject({ ok: true, balance: { packSeconds: 100 } });
    // Older packs are spent first.
    await b.settle("r2", 40, T0);
    expect(await b.takeBackPack("refund:adj_2:txnitm_b", "txn_b:pri_pack_5h", 100, T0)).toBe(60);
  });

  it("is out of hours only at zero", async () => {
    const b = balance();
    expect(await b.authorize("r1", 1, 1, 0, T0)).toEqual({ ok: false, reason: "out_of_hours" });
  });

  it("rejects a session generation after sign out everywhere", async () => {
    const b = balance();
    const { generation } = await b.signIn(HOUR, T0);
    expect(await b.signOutEverywhere(generation)).toBe(true);
    expect(await b.signOutEverywhere(generation)).toBe(false);
    expect(await b.authorize("r1", 1, 1, generation, T0)).toEqual({ ok: false, reason: "signed_out" });
    expect(await b.account(generation, T0)).toEqual({ ok: false, reason: "signed_out" });
  });

  it("grants the trial once", async () => {
    const b = balance();
    expect(await b.signIn(HOUR, T0)).toEqual({ generation: 0, trialGranted: true });
    expect(await b.signIn(HOUR, T0)).toEqual({ generation: 0, trialGranted: false });
    expect(await b.account(0, T0)).toMatchObject({ balance: { secondsLeft: HOUR } });
  });

  it("resets an annual plan's hours each month and ends them with the period", async () => {
    const b = balance();
    const start = Date.UTC(2026, 0, 31);
    const end = Date.UTC(2027, 0, 31);
    await b.startPlan(
      "txn_a:pri_pro_annual",
      { subscriptionId: "sub_1", monthlySeconds: 8 * HOUR, periodStart: start, periodEnd: end },
      start,
    );
    await b.settle("r1", 3 * HOUR, start + DAY);
    expect(await b.account(0, start + DAY)).toMatchObject({
      balance: { planSecondsLeft: 5 * HOUR, planResetsAt: Date.UTC(2026, 1, 28) },
    });
    // Unused hours do not carry over.
    expect(await b.account(0, Date.UTC(2026, 1, 28))).toMatchObject({
      balance: { planSecondsLeft: 8 * HOUR, planResetsAt: Date.UTC(2026, 2, 31), planPeriodEnd: end },
    });
    expect(await b.account(0, end)).toMatchObject({
      balance: { planSecondsLeft: 0, planPeriodEnd: 0, planResetsAt: 0 },
    });
  });

  it("ends the plan at once on cancel and keeps pack hours", async () => {
    const b = balance();
    await b.addPack("p", 100, T0);
    await b.startPlan(
      "t",
      { subscriptionId: "sub_1", monthlySeconds: 8 * HOUR, periodStart: T0, periodEnd: T0 + 30 * DAY },
      T0,
    );
    await b.endPlan("sub_1", true, T0 + DAY);
    expect(await b.account(0, T0 + DAY)).toMatchObject({
      balance: { secondsLeft: 100, planSecondsLeft: 0, planPeriodEnd: 0 },
    });
  });
});

describe("Balance plans and Paddle's event order", () => {
  const period = (n: number, sub = "sub_1") => ({
    subscriptionId: sub,
    monthlySeconds: 8 * HOUR,
    periodStart: T0 + n * 30 * DAY,
    periodEnd: T0 + (n + 1) * 30 * DAY,
  });

  it("ignores a late retry of an older period of the same subscription", async () => {
    const b = balance();
    expect(await b.startPlan("txn_2", period(1), T0 + 30 * DAY)).toBe(true);
    await b.settle("r1", HOUR, T0 + 30 * DAY);
    expect(await b.startPlan("txn_1", period(0), T0 + 30 * DAY)).toBe(false);
    expect(await b.account(0, T0 + 30 * DAY)).toMatchObject({
      balance: { planSecondsLeft: 7 * HOUR, planPeriodEnd: period(1).periodEnd },
    });
  });

  it("does not let a cancel of an old subscription end the new one's plan", async () => {
    const b = balance();
    await b.startPlan("txn_b", period(0, "sub_b"), T0);
    await b.endPlan("sub_a", true, T0);
    expect(await b.account(0, T0)).toMatchObject({ balance: { planSecondsLeft: 8 * HOUR } });
  });

  it("blocks any later period of a canceled subscription, but not of a paused one", async () => {
    const canceled = balance();
    await canceled.endPlan("sub_1", true, T0);
    expect(await canceled.startPlan("txn_late", period(0), T0)).toBe(false);

    const paused = balance();
    await paused.startPlan("txn_1", period(0), T0);
    await paused.endPlan("sub_1", false, T0 + DAY);
    expect(await paused.account(0, T0 + DAY)).toMatchObject({ balance: { planSecondsLeft: 0 } });
    expect(await paused.startPlan("txn_resume", period(1), T0 + 30 * DAY)).toBe(true);
  });
});

describe("windowEnd", () => {
  it("counts calendar months from the period start, capped at the period end", () => {
    const start = Date.UTC(2026, 0, 31);
    expect(windowEnd(start, Date.UTC(2027, 0, 31), start)).toBe(Date.UTC(2026, 1, 28));
    expect(windowEnd(start, Date.UTC(2027, 0, 31), Date.UTC(2026, 6, 1))).toBe(Date.UTC(2026, 6, 31));
    expect(windowEnd(start, Date.UTC(2026, 1, 28), start)).toBe(Date.UTC(2026, 1, 28));
  });
});
