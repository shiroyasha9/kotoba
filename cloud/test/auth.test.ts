import { describe, expect, it } from "vitest";
import { CODE_ATTEMPTS, CODE_TTL_MS, RESEND_MS } from "../src/auth";
import { SESSION_DAYS } from "../src/session";
import { account, bearer, DAY, errorCode, harness, json, newEmail, signIn } from "./helpers";

function wrong(code: string): string {
  return String((Number(code) + 1) % 1_000_000).padStart(6, "0");
}

describe("email sign-in", () => {
  it("makes the account, grants the free hour once, and keeps the user id on the next sign-in", async () => {
    const h = harness();
    const email = newEmail();
    const ip = "192.0.2.10";
    expect((await h.fetch("/auth/start", json({ email: ` ${email.toUpperCase()} ` }, ip))).status).toBe(202);
    const code = h.mailer.codes.get(email);
    expect(code).toMatch(/^\d{6}$/);
    const first = await h.fetch("/auth/verify", json({ email, code }, ip));
    expect(first.status).toBe(200);
    const body = await first.json<{ token: string; user: { id: string }; trial_granted: boolean }>();
    expect(body.trial_granted).toBe(true);
    expect(body.token).toMatch(/^v1\./);

    expect(await account(h, body.token)).toMatchObject({
      user: { id: body.user.id, email },
      plan: null,
      seconds_left: 3600,
      pack_seconds: 3600,
    });

    h.clock.now += RESEND_MS;
    await h.fetch("/auth/start", json({ email }, ip));
    const again = await h.fetch("/auth/verify", json({ email, code: h.mailer.codes.get(email) }, ip));
    expect(await again.json()).toMatchObject({ user: { id: body.user.id }, trial_granted: false });
  });

  it("allows a few wrong codes, then makes the code useless", async () => {
    const h = harness();
    const email = newEmail();
    const ip = "192.0.2.11";
    await h.fetch("/auth/start", json({ email }, ip));
    const code = h.mailer.codes.get(email) ?? "";
    const bad = await h.fetch("/auth/verify", json({ email, code: wrong(code) }, ip));
    expect([bad.status, await errorCode(bad)]).toEqual([400, "code_invalid"]);
    for (let i = 1; i < CODE_ATTEMPTS; i++) await h.fetch("/auth/verify", json({ email, code: wrong(code) }, ip));
    const late = await h.fetch("/auth/verify", json({ email, code }, ip));
    expect(await errorCode(late)).toBe("code_expired");
    // Asking for a new code does not buy more guesses while the used-up one lives.
    h.clock.now += RESEND_MS;
    const again = await h.fetch("/auth/start", json({ email }, ip));
    expect([again.status, await errorCode(again)]).toEqual([429, "rate_limited"]);
    h.clock.now += CODE_TTL_MS;
    expect((await h.fetch("/auth/start", json({ email }, ip))).status).toBe(202);
  });

  it("keeps the count of wrong tries when a new code replaces the old one", async () => {
    const h = harness();
    const email = newEmail();
    const ip = "192.0.2.15";
    await h.fetch("/auth/start", json({ email }, ip));
    const first = h.mailer.codes.get(email) ?? "";
    for (let i = 0; i < CODE_ATTEMPTS - 1; i++) await h.fetch("/auth/verify", json({ email, code: wrong(first) }, ip));
    h.clock.now += RESEND_MS;
    await h.fetch("/auth/start", json({ email }, ip));
    const second = h.mailer.codes.get(email) ?? "";
    expect(await errorCode(await h.fetch("/auth/verify", json({ email, code: wrong(second) }, ip)))).toBe(
      "code_invalid",
    );
    expect(await errorCode(await h.fetch("/auth/verify", json({ email, code: second }, ip)))).toBe("code_expired");
  });

  it("expires a code after its lifetime", async () => {
    const h = harness();
    const email = newEmail();
    await h.fetch("/auth/start", json({ email }, "192.0.2.12"));
    h.clock.now += CODE_TTL_MS;
    const late = await h.fetch("/auth/verify", json({ email, code: h.mailer.codes.get(email) }, "192.0.2.12"));
    expect(await errorCode(late)).toBe("code_expired");
  });

  it("sends a new code at most once in 30 seconds per email", async () => {
    const h = harness();
    const email = newEmail();
    await h.fetch("/auth/start", json({ email }, "192.0.2.13"));
    const soon = await h.fetch("/auth/start", json({ email }, "192.0.2.13"));
    expect([soon.status, await errorCode(soon)]).toEqual([429, "rate_limited"]);
    expect(soon.headers.get("Retry-After")).toBe("30");
  });

  it("refuses a bad email and a code that is not six digits", async () => {
    const h = harness();
    const badEmail = await h.fetch("/auth/start", json({ email: "not-an-email" }, "192.0.2.14"));
    expect([badEmail.status, await errorCode(badEmail)]).toEqual([400, "invalid_email"]);
    const badCode = await h.fetch("/auth/verify", json({ email: newEmail(), code: "12ab" }, "192.0.2.14"));
    expect(await errorCode(badCode)).toBe("code_invalid");
    const notJson = await h.fetch("/auth/start", {
      method: "POST",
      body: "email=x",
      headers: { "CF-Connecting-IP": "192.0.2.14" },
    });
    expect(await errorCode(notJson)).toBe("bad_request");
  });

  it("limits sign-in tries per client IP", async () => {
    const h = harness();
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++)
      statuses.push((await h.fetch("/auth/start", json({ email: newEmail() }, "192.0.2.99"))).status);
    expect(statuses.slice(0, 10).every((s) => s === 202)).toBe(true);
    expect(statuses[10]).toBe(429);
  });

  it("renews a token older than 30 days in X-Kotoba-Token, on a successful request", async () => {
    const h = harness();
    const { token } = await signIn(h);
    h.clock.now += 29 * DAY;
    expect((await h.fetch("/v1/account", bearer(token))).headers.get("X-Kotoba-Token")).toBeNull();
    h.clock.now += 2 * DAY;
    const response = await h.fetch("/v1/account", bearer(token));
    const renewed = response.headers.get("X-Kotoba-Token");
    expect(renewed).toMatch(/^v1\./);
    expect(response.headers.get("X-Kotoba-Token-Expires")).toBe(
      new Date(h.clock.now + SESSION_DAYS * DAY).toISOString(),
    );
    // The old token still works until it expires; the new one lives 180 days from now.
    h.clock.now += 170 * DAY;
    expect((await h.fetch("/v1/account", bearer(token))).status).toBe(401);
    expect((await h.fetch("/v1/account", bearer(renewed ?? ""))).status).toBe(200);
  });
});
