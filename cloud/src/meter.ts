import { DurableObject } from "cloudflare:workers";

/**
 * Audio seconds of all users in one UTC day (one object per day, named `YYYY-MM-DD`). A bug or a stolen token cannot
 * spend more than GLOBAL_DAILY_CAP_SECONDS a day: past the cap every dictation gets `service_paused`. One call per
 * dictation, at the gate, in parallel with the upstream request; it counts the expected length, not the billed one,
 * which is near enough for a safety cap.
 */
export class GlobalMeter extends DurableObject<Env> {
  private readonly sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS meter (id INTEGER PRIMARY KEY CHECK (id = 1), seconds INTEGER NOT NULL);
      INSERT OR IGNORE INTO meter (id, seconds) VALUES (1, 0);`);
  }

  /** Counts `seconds` and returns true while the day is under `cap`; past it, counts nothing and returns false. */
  charge(cap: number, seconds: number): boolean {
    return (
      this.sql
        .exec("UPDATE meter SET seconds = seconds + ? WHERE seconds < ? RETURNING seconds", seconds, cap)
        .toArray().length > 0
    );
  }
}

export function meterName(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}
