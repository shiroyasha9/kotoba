import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { defaultDeps } from "../src/app";
import { errorCode, harness, json } from "./helpers";

/** `/auth/start` through the deployed mailer choice, under `environment`. */
function startSignIn(environment: string, email: string): Promise<Response> {
  return harness(undefined, defaultDeps.mailer).fetch("/auth/start", json({ email }, "192.0.2.200"), {
    ENVIRONMENT: environment,
  });
}

afterEach(() => vi.restoreAllMocks());

describe("the sign-in mailer", () => {
  it("refuses to start sign-in outside dev until a real mailer is wired, and logs no code", async () => {
    const log = vi.spyOn(console, "log");
    const response = await startSignIn("production", "prod@example.com");
    expect([response.status, await errorCode(response)]).toEqual([500, "mailer_not_configured"]);
    expect(log.mock.calls.flat().join(" ")).not.toMatch(/\d{6}/);
    const row = await env.DB.prepare("SELECT 1 FROM auth_codes WHERE email = ?").bind("prod@example.com").first();
    expect(row).toBeNull();
  });

  it("prints the code in dev, with the email masked", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    expect((await startSignIn("dev", "devuser@example.com")).status).toBe(202);
    const line = log.mock.calls.flat().join(" ");
    expect(line).toMatch(/sign-in code for d\*+@example\.com: \d{6}/);
    expect(line).not.toContain("devuser@");
  });
});
