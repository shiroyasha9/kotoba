import type { ContentfulStatusCode } from "hono/utils/http-status";

/** Every error code the client can get. The README's error table lists the same codes; the app maps each one. */
export type ErrorCode =
  | "bad_request"
  | "invalid_email"
  | "code_invalid"
  | "code_expired"
  | "signed_out"
  | "out_of_hours"
  | "audio_too_large"
  | "audio_too_long"
  | "bad_audio"
  | "unsupported_media_type"
  | "rate_limited"
  | "service_paused"
  | "upstream_busy"
  | "upstream_failed"
  | "upstream_timeout"
  | "bad_signature"
  | "not_implemented"
  | "internal";

/** An error the client sees as `{"error": {"code", "message"}}` with `status`. Anything else is a 500. */
export class ApiError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: ErrorCode,
    message: string,
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
  }

  toResponse(): Response {
    return Response.json(
      { error: { code: this.code, message: this.message } },
      { status: this.status, headers: this.headers },
    );
  }
}

export function signedOut(): ApiError {
  return new ApiError(401, "signed_out", "Sign in to kotoba Cloud again.");
}

/** A numeric `vars` entry; a missing or bad one fails loudly instead of turning into NaN and passing every check. */
export function numberVar(env: Env, name: keyof Env): number {
  const value = env[name];
  const number = typeof value === "string" && value !== "" ? Number(value) : Number.NaN;
  if (!Number.isFinite(number)) throw new Error(`${name} is not a number`);
  return number;
}
