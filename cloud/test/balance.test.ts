import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { HOLD_MS, windowEnd } from "../src/balance";
import { T0 } from "./helpers";

const HOUR = 3600;
const DAY = 86_400_000;

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
    expect(await b.authorize("r1", 150, 0, T0)).toMatchObject({ ok: true, balance: { secondsLeft: 5 * HOUR + 100 } });
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

  it("holds the last seconds for one dictation at a time, until the hold is settled, released or lapses", async () => {
    const b = balance();
    await b.addPack("p", 30, T0);
    expect(await b.authorize("r1", 60, 0, T0)).toMatchObject({ ok: true });
    expect(await b.authorize("r2", 5, 0, T0)).toEqual({ ok: false, reason: "out_of_hours" });
    await b.release("r1");
    expect(await b.authorize("r3", 60, 0, T0)).toMatchObject({ ok: true });
    expect(await b.authorize("r4", 5, 0, T0 + HOLD_MS)).toMatchObject({ ok: true });
  });

  it("rejects a session generation after sign out everywhere", async () => {
    const b = balance();
    const { generation } = await b.signIn(HOUR, T0);
    expect(await b.signOutEverywhere(generation)).toBe(true);
    expect(await b.signOutEverywhere(generation)).toBe(false);
    expect(await b.authorize("r1", 1, generation, T0)).toEqual({ ok: false, reason: "signed_out" });
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
