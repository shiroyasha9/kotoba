import { DurableObject } from "cloudflare:workers";
import { numberVar } from "./errors";

/**
 * One Balance object per user (named by user id) holds the hours: SQLite storage, single-threaded, so every change is
 * atomic. Plan hours (Pro, reset each month) are spent before pack hours (never expire). Each pack (and the trial)
 * keeps its own seconds left, spent oldest first, so a refund takes back only what is left of that pack.
 *
 * A dictation starts (`authorize`, in parallel with the upstream request) when the seconds not yet held cover its
 * stated length, and holds the byte-count bound, at most the free seconds. After the response it pays its real length,
 * at most the hold (`settle`). So no balance goes below zero, an honest recording needs only its own length, and a
 * client that understates the length gets at most the rest of its balance. An unsettled hold lapses after HOLD_MS.
 * Every method takes `now` (ms) from the Worker, so tests control the clock.
 */
export const HOLD_MS = 10 * 60 * 1000;
/** `use` rows only guard a settle against a repeat; after this long they go. Credits stay for good. */
export const USE_ROWS_KEPT_MS = 30 * 24 * 60 * 60 * 1000;

export interface BalanceSnapshot {
  /** Plan seconds left this month plus pack seconds. */
  secondsLeft: number;
  planSecondsLeft: number;
  packSeconds: number;
  /** Unix ms; 0 when there is no active plan. */
  planPeriodEnd: number;
  /** Unix ms when the plan's monthly hours reset; 0 when there is no active plan. */
  planResetsAt: number;
}

type Refusal<R extends string> = { ok: false; reason: R };
export type Authorization =
  | { ok: true; balance: BalanceSnapshot; hold: number }
  | Refusal<"signed_out" | "out_of_hours" | "not_enough_hours">;
export type AccountReply = { ok: true; balance: BalanceSnapshot } | Refusal<"signed_out">;

export interface Plan {
  /** The Paddle subscription the period belongs to. */
  subscriptionId: string;
  monthlySeconds: number;
  /** Unix ms of the paid period, from Paddle's `billing_period`. */
  periodStart: number;
  periodEnd: number;
}

type LedgerKind = "trial" | "pack" | "plan" | "plan_end" | "use" | "refund";

interface AccountRow extends Record<string, SqlStorageValue> {
  /** The sum of `packs.seconds_left`. */
  pack_seconds: number;
  plan_subscription_id: string | null;
  /** The ledger ref of the payment that started the current period. */
  plan_ref: string | null;
  plan_monthly_seconds: number;
  plan_seconds_left: number;
  plan_period_start: number;
  plan_period_end: number;
  /** 0 when no plan is active. */
  plan_window_end: number;
  session_gen: number;
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS account (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  plan_subscription_id TEXT,
  plan_ref TEXT,
  plan_monthly_seconds INTEGER NOT NULL DEFAULT 0,
  plan_seconds_left INTEGER NOT NULL DEFAULT 0,
  plan_period_start INTEGER NOT NULL DEFAULT 0,
  plan_period_end INTEGER NOT NULL DEFAULT 0,
  plan_window_end INTEGER NOT NULL DEFAULT 0,
  session_gen INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO account (id) VALUES (1);
CREATE TABLE IF NOT EXISTS ledger (
  ref TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  kind TEXT NOT NULL,
  plan_seconds INTEGER NOT NULL,
  pack_seconds INTEGER NOT NULL,
  absorbed_seconds INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ledger_kind_at ON ledger (kind, at);
CREATE TABLE IF NOT EXISTS packs (
  ref TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  granted INTEGER NOT NULL,
  seconds_left INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS holds (
  request_id TEXT PRIMARY KEY,
  seconds INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);`;

export class Balance extends DurableObject<Env> {
  private readonly sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(SCHEMA);
  }

  /** Called at sign-in: grants the free trial once per user and returns the session generation for the token. */
  signIn(trialSeconds: number, now: number): { generation: number; trialGranted: boolean } {
    return this.ctx.storage.transactionSync(() => {
      const trialGranted = this.addPackSeconds("trial", "trial", trialSeconds, now);
      return { generation: this.row(now).session_gen, trialGranted };
    });
  }

  /** Ends every session token (they carry the old generation). A token that is already ended cannot do it again. */
  signOutEverywhere(generation: number): boolean {
    const rows = this.sql
      .exec("UPDATE account SET session_gen = session_gen + 1 WHERE session_gen = ? RETURNING session_gen", generation)
      .toArray();
    return rows.length > 0;
  }

  account(generation: number, now: number): AccountReply {
    const row = this.row(now);
    if (row.session_gen !== generation) return { ok: false, reason: "signed_out" };
    return { ok: true, balance: snapshot(row) };
  }

  /**
   * Starts a dictation when the seconds not yet held cover `stated` (its claimed length, at least 1), and holds
   * `maxHold` (the byte-count bound), at most the free seconds.
   */
  authorize(requestId: string, stated: number, maxHold: number, generation: number, now: number): Authorization {
    return this.ctx.storage.transactionSync(() => {
      const row = this.row(now);
      if (row.session_gen !== generation) return { ok: false, reason: "signed_out" } as const;
      this.sql.exec("DELETE FROM holds WHERE expires_at <= ?", now);
      const held = this.sql.exec<{ held: number }>("SELECT COALESCE(SUM(seconds), 0) AS held FROM holds").one().held;
      const balance = snapshot(row);
      if (balance.secondsLeft <= 0) return { ok: false, reason: "out_of_hours" } as const;
      const free = balance.secondsLeft - held;
      // A hold is cut to the free seconds only when no other dictation is open: else a parallel dictation with a short
      // claim could take the cut while the first one holds the rest, and repeat.
      if (free < stated || (free < maxHold && held > 0)) return { ok: false, reason: "not_enough_hours" } as const;
      const hold = Math.min(maxHold, free);
      this.sql.exec(
        "INSERT OR REPLACE INTO holds (request_id, seconds, expires_at) VALUES (?, ?, ?)",
        requestId,
        hold,
        now + HOLD_MS,
      );
      return { ok: true, balance, hold } as const;
    });
  }

  /**
   * Pays a dictation's real length, at most its hold: plan seconds first, then pack seconds. Runs once per request id.
   * Returns the balance after.
   */
  settle(requestId: string, seconds: number, now: number): BalanceSnapshot {
    return this.ctx.storage.transactionSync(() => {
      const row = this.row(now);
      const hold = this.sql
        .exec<{ seconds: number }>("DELETE FROM holds WHERE request_id = ? RETURNING seconds", requestId)
        .toArray()[0];
      if (this.has(requestId)) return snapshot(row);
      if (hold) seconds = Math.min(seconds, hold.seconds);
      const { fromPlan, fromPack } = spend(row.plan_seconds_left, row.pack_seconds, seconds);
      this.sql.exec("UPDATE account SET plan_seconds_left = plan_seconds_left - ?", fromPlan);
      this.spendPacks(fromPack);
      this.record(requestId, "use", now, -fromPlan, -fromPack, seconds - fromPlan - fromPack);
      this.sql.exec("DELETE FROM ledger WHERE kind = 'use' AND at < ?", now - USE_ROWS_KEPT_MS);
      return snapshot(this.row(now));
    });
  }

  /** Drops a hold when the dictation failed before it cost anything. Safe to call for any id. */
  release(requestId: string): void {
    this.sql.exec("DELETE FROM holds WHERE request_id = ?", requestId);
  }

  /** Adds pack seconds once per `ref` (a Paddle transaction and price). Returns false for a repeat. */
  addPack(ref: string, seconds: number, now: number): boolean {
    return this.ctx.storage.transactionSync(() => this.addPackSeconds(ref, "pack", seconds, now));
  }

  /**
   * Takes back up to `seconds` of the pack `packRef` once per `ref`: only what is left of that pack, never below zero
   * (used hours are not a debt). Returns the seconds taken back.
   */
  takeBackPack(ref: string, packRef: string, seconds: number, now: number): number {
    return this.ctx.storage.transactionSync(() => {
      if (this.has(ref)) return 0;
      const pack = this.sql
        .exec<{ seconds_left: number }>("SELECT seconds_left FROM packs WHERE ref = ?", packRef)
        .toArray()[0];
      const taken = Math.min(seconds, pack?.seconds_left ?? 0);
      this.sql.exec("UPDATE packs SET seconds_left = seconds_left - ? WHERE ref = ?", taken, packRef);
      this.record(ref, "refund", now, 0, -taken);
      return taken;
    });
  }

  /**
   * Takes back a refunded plan payment once per `ref`. `share` (of the money) of the period's monthly seconds comes off
   * every month that is left, so an annual plan stays smaller too; this month's cut comes from its unused seconds,
   * never below zero. When the shares reach the whole, the period ends. Only the current period has seconds to take:
   * an older one has already reset or ended. A later subscription event that ends the plan finds nothing more to take.
   */
  takeBackPlan(ref: string, planRef: string, share: number, now: number): number {
    return this.ctx.storage.transactionSync(() => {
      if (this.has(ref)) return 0;
      const row = this.row(now);
      let taken = 0;
      if (row.plan_ref === planRef && row.plan_window_end !== 0) {
        // The share is of the hours the payment bought, so several partial refunds add up as their money does.
        const bought = this.sql
          .exec<{ plan_seconds: number }>("SELECT plan_seconds FROM ledger WHERE ref = ?", planRef)
          .one().plan_seconds;
        const monthly = Math.max(0, row.plan_monthly_seconds - Math.floor(bought * share));
        taken = Math.min(row.plan_seconds_left, row.plan_monthly_seconds - monthly);
        if (monthly === 0) {
          this.sql.exec("UPDATE account SET plan_monthly_seconds = 0, plan_seconds_left = 0, plan_window_end = 0");
        } else {
          this.sql.exec(
            "UPDATE account SET plan_monthly_seconds = ?, plan_seconds_left = plan_seconds_left - ?",
            monthly,
            taken,
          );
        }
      }
      this.record(ref, "refund", now, -taken, 0);
      return taken;
    });
  }

  /**
   * Starts a paid plan period once per `ref` (the Paddle transaction). The monthly hours reset now; an annual period
   * resets them again each month (`row`). Unused plan hours do not carry over. A late retry of an older period of the
   * same subscription, or any period of a canceled one, changes nothing.
   */
  startPlan(ref: string, plan: Plan, now: number): boolean {
    return this.ctx.storage.transactionSync(() => {
      if (this.has(ref) || this.has(planEndRef(plan.subscriptionId))) return false;
      const row = this.row(now);
      if (row.plan_subscription_id === plan.subscriptionId && plan.periodEnd <= row.plan_period_end) return false;
      this.sql.exec(
        `UPDATE account SET plan_subscription_id = ?, plan_ref = ?, plan_monthly_seconds = ?, plan_seconds_left = ?,
           plan_period_start = ?, plan_period_end = ?, plan_window_end = ?`,
        plan.subscriptionId,
        ref,
        plan.monthlySeconds,
        plan.monthlySeconds,
        plan.periodStart,
        plan.periodEnd,
        windowEnd(plan.periodStart, plan.periodEnd, Math.max(now, plan.periodStart)),
      );
      this.record(ref, "plan", now, plan.monthlySeconds, 0);
      return true;
    });
  }

  /**
   * Ends the plan of `subscriptionId` now; a plan of another subscription stays. `final` (Paddle canceled it, which
   * cannot be undone) also blocks any late period of that subscription. A pause is not final. Pack hours stay.
   */
  endPlan(subscriptionId: string, final: boolean, now: number): void {
    this.ctx.storage.transactionSync(() => {
      const ref = planEndRef(subscriptionId);
      if (final && !this.has(ref)) this.record(ref, "plan_end", now, 0, 0);
      this.sql.exec(
        "UPDATE account SET plan_seconds_left = 0, plan_window_end = 0 WHERE plan_subscription_id = ?",
        subscriptionId,
      );
    });
  }

  private addPackSeconds(ref: string, kind: LedgerKind, seconds: number, now: number): boolean {
    if (this.has(ref)) return false;
    this.sql.exec("INSERT INTO packs (ref, at, granted, seconds_left) VALUES (?, ?, ?, ?)", ref, now, seconds, seconds);
    this.record(ref, kind, now, 0, seconds);
    return true;
  }

  /** Spends `seconds` of pack time, oldest pack first. The caller checked they are there. */
  private spendPacks(seconds: number): void {
    let rest = seconds;
    const packs = this.sql
      .exec<{ ref: string; seconds_left: number }>(
        "SELECT ref, seconds_left FROM packs WHERE seconds_left > 0 ORDER BY at, ref",
      )
      .toArray();
    for (const pack of packs) {
      if (rest === 0) break;
      const take = Math.min(rest, pack.seconds_left);
      this.sql.exec("UPDATE packs SET seconds_left = seconds_left - ? WHERE ref = ?", take, pack.ref);
      rest -= take;
    }
  }

  private record(ref: string, kind: LedgerKind, now: number, planSeconds: number, packSeconds: number, absorbed = 0) {
    this.sql.exec(
      "INSERT INTO ledger (ref, at, kind, plan_seconds, pack_seconds, absorbed_seconds) VALUES (?, ?, ?, ?, ?, ?)",
      ref,
      now,
      kind,
      planSeconds,
      packSeconds,
      absorbed,
    );
  }

  private has(ref: string): boolean {
    return this.sql.exec("SELECT 1 FROM ledger WHERE ref = ?", ref).toArray().length > 0;
  }

  /** The account row at `now`; first resets the plan's monthly hours when a new month of the period has begun. */
  private row(now: number): AccountRow {
    const row = this.sql
      .exec<AccountRow>(
        "SELECT *, (SELECT COALESCE(SUM(seconds_left), 0) FROM packs) AS pack_seconds FROM account WHERE id = 1",
      )
      .one();
    if (row.plan_window_end === 0 || now < row.plan_window_end) return row;
    if (now >= row.plan_period_end) {
      this.sql.exec("UPDATE account SET plan_seconds_left = 0, plan_window_end = 0");
      return { ...row, plan_seconds_left: 0, plan_window_end: 0 };
    }
    const next = windowEnd(row.plan_period_start, row.plan_period_end, now);
    this.sql.exec("UPDATE account SET plan_seconds_left = plan_monthly_seconds, plan_window_end = ?", next);
    return { ...row, plan_seconds_left: row.plan_monthly_seconds, plan_window_end: next };
  }
}

function planEndRef(subscriptionId: string): string {
  return `end:${subscriptionId}`;
}

/** Plan seconds first, then pack seconds. What neither covers (a plan period that ended mid-dictation) is absorbed. */
export function spend(planSeconds: number, packSeconds: number, seconds: number) {
  const fromPlan = Math.min(seconds, planSeconds);
  return { fromPlan, fromPack: Math.min(seconds - fromPlan, packSeconds) };
}

/**
 * The byte-count bound of a dictation: the most seconds `bytes` of FLAC can hold at the lowest bitrate the relay bills
 * in full, at least 1, at most `maxSeconds`.
 */
export function holdFor(bytes: number, limits: AudioLimits): number {
  return Math.min(limits.maxSeconds, Math.max(1, Math.ceil(bytes / limits.minBytesPerSecond)));
}

export interface AudioLimits {
  maxBytes: number;
  maxSeconds: number;
  minBytesPerSecond: number;
}

export function audioLimits(env: Env): AudioLimits {
  return {
    maxBytes: numberVar(env, "MAX_AUDIO_BYTES"),
    maxSeconds: numberVar(env, "MAX_AUDIO_SECONDS"),
    minBytesPerSecond: numberVar(env, "MIN_AUDIO_BYTES_PER_SECOND"),
  };
}

/** The balance after paying `seconds`, as `settle` will leave it. */
export function afterPaying(balance: BalanceSnapshot, seconds: number): BalanceSnapshot {
  const { fromPlan, fromPack } = spend(balance.planSecondsLeft, balance.packSeconds, seconds);
  return {
    ...balance,
    secondsLeft: balance.secondsLeft - fromPlan - fromPack,
    planSecondsLeft: balance.planSecondsLeft - fromPlan,
    packSeconds: balance.packSeconds - fromPack,
  };
}

function snapshot(row: AccountRow): BalanceSnapshot {
  const active = row.plan_window_end !== 0;
  return {
    secondsLeft: row.plan_seconds_left + row.pack_seconds,
    planSecondsLeft: row.plan_seconds_left,
    packSeconds: row.pack_seconds,
    planPeriodEnd: active ? row.plan_period_end : 0,
    planResetsAt: row.plan_window_end,
  };
}

/** The end of the plan month that holds `at`: whole calendar months from the period start, capped at the period end. */
export function windowEnd(periodStart: number, periodEnd: number, at: number): number {
  for (let months = 1; ; months++) {
    const end = addMonths(periodStart, months);
    if (end >= periodEnd) return periodEnd;
    if (end > at) return end;
  }
}

function addMonths(ms: number, months: number): number {
  const date = new Date(ms);
  const day = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + months);
  // Jan 31 + 1 month is the last day of February, as billing systems count it.
  const last = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
  date.setUTCDate(Math.min(day, last));
  return date.getTime();
}
