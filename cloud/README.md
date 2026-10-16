# kotoba Cloud relay

Hosted dictation for kotoba with no API key of your own: the app sends its FLAC recording here, the relay sends it to
Azure MAI-Transcribe-2 and returns the text, and the user pays in prepaid audio hours. BYOK (your own OpenRouter key)
stays free and needs no account; kotoba Cloud is opt-in.

**Status: local prototype.** It runs under `wrangler dev` (Miniflare) and vitest only. Nothing is deployed, no
Cloudflare, Paddle, Azure or email account exists, and no real payment or upstream call is made.

Design: a Cloudflare Worker (Hono) at the Mumbai edge, D1 for users and purchases, one Durable Object per user for the
balance, Paddle Billing as the Merchant of Record, Azure Speech in `centralindia`. Why Azure direct and not OpenRouter:
OpenRouter's terms forbid reselling API access.

## Layout

| Path | What |
|---|---|
| `src/app.ts` | Routes, dependencies (`Deps`: clock, transcriber, mailer), error handler |
| `src/transcribe.ts` | `POST /v1/transcribe`, the hot path; `POST /v1/cleanup` (501) |
| `src/upstream.ts` | `Transcriber` interface, `AzureTranscriber`, `FakeTranscriber` |
| `src/balance.ts` | `Balance` Durable Object: holds, settle, packs, plan months, session generation |
| `src/meter.ts` | `GlobalMeter` Durable Object: all users' seconds per UTC day, against the daily cap |
| `src/auth.ts`, `src/session.ts` | Email codes, sealed session tokens |
| `src/account.ts` | `GET /v1/account`, `POST /v1/sign-out-everywhere` |
| `src/paddle.ts` | `POST /billing/paddle` webhooks and signature check |
| `src/flac.ts` | FLAC STREAMINFO reader |
| `migrations/` | D1 schema |
| `test/` | vitest in workerd (`@cloudflare/vitest-plugin`); Paddle fixture payloads in `test/fixtures/` |
| `scripts/` | `fake-azure.ts` (local Azure stand-in), `latency.ts` (overhead bench) |

## Run it locally

```sh
cd cloud
bun install
cp .dev.vars.example .dev.vars   # test placeholders, not secrets
bun run db:migrate               # local D1 only
bun run dev                      # http://localhost:8787, fake upstream
```

Sign-in codes print in the `wrangler dev` log (`MAILER=console`). To run the real `AzureTranscriber` against a local
Azure stand-in: `bun run fake-azure` in one terminal, then
`bun run dev -- --var UPSTREAM:azure --var AZURE_ENDPOINT:http://127.0.0.1:8788`.

Checks: `bun run test`, `bun run typecheck`, `bun run lint` (Biome; `bun run format` fixes). This folder is outside
`make check`; the repo's `make privacy` covers it.

## API contract

Base URL: not chosen yet (a custom domain on the Worker). All bodies are JSON unless a row says otherwise. Times are
ISO 8601 UTC. Lengths of audio are in seconds.

### Errors

Every error is `{"error": {"code": "<code>", "message": "<text for the person>"}}` with the status below. The app maps
the `code`, not the message.

| Status | `code` | When | App action |
|---|---|---|---|
| 400 | `bad_request` | A header or body field is wrong | Bug: log it, do not retry |
| 400 | `invalid_email` | `/auth/start` email is not an address | Show the message |
| 400 | `code_invalid` | Wrong or malformed sign-in code | Let the person try again |
| 400 | `code_expired` | Code too old, used up (5 wrong tries) or never sent | Ask for a new code |
| 400 | `bad_audio` | Not 16 kHz mono 16-bit FLAC (checked from STREAMINFO before any upstream call), the upstream cannot read it, or the upstream heard more audio than the bytes can hold at the lowest allowed bitrate (a muted microphone or a crafted file; the hold is paid, no text) | Do not retry this recording |
| 401 | `signed_out` | No token, bad or expired token, or "Sign out everywhere" ended it | Delete the token, show sign-in; keep the recording queued |
| 401 | `bad_signature` | Paddle webhook signature check failed | (Paddle only) |
| 402 | `out_of_hours` | No hours left | Keep the recording queued; show Buy Hours and Use My Own Key |
| 402 | `not_enough_hours` | Some hours are left, but fewer than this recording's length | Same as `out_of_hours`; the app should have caught it before the upload (see "Before upload") |
| 411 | `length_required` | No `Content-Length` | Bug |
| 413 | `audio_too_long` | Over `MAX_AUDIO_SECONDS` (1,200 s) | Do not retry |
| 413 | `audio_too_large` | Over `MAX_AUDIO_BYTES` (32 MiB), or more bytes than `Content-Length` | Do not retry |
| 415 | `unsupported_media_type` | `Content-Type` is not `audio/flac` | Bug |
| 429 | `rate_limited` | Too many dictations a minute (30 per user) or sign-in tries (10 a minute per IP; one code per email each 30 s) | Retry after `Retry-After` seconds |
| 501 | `not_implemented` | `/v1/cleanup` | Use the app's own cleanup route |
| 502 | `upstream_failed` | Azure failed | Retry with backoff (the retry queue) |
| 503 | `upstream_busy` | Azure answered 429 or 503 | Retry after `Retry-After` |
| 503 | `service_paused` | The global daily cap is reached | Retry later; show "kotoba Cloud is paused" |
| 504 | `upstream_timeout` | No answer in `UPSTREAM_TIMEOUT_MS` (120 s, upload included) | Retry |
| 500 | `internal` | A bug in the relay | Retry with backoff |

A failed dictation costs nothing: the hold is released and the global meter gets its seconds back. Only a 200 (and
the `bad_audio` case above) is paid for.

### `POST /auth/start`

Body `{"email": "me@example.com"}`. Sends a six-digit code that lives 10 minutes. Answer `202 {"ok": true}`, the same
for a new or a known email. A new code replaces the old one at most every 30 s and keeps its count of wrong tries.

### `POST /auth/verify`

Body `{"email": "me@example.com", "code": "123456"}`. Makes the account on first sign-in and grants the free hour
(3,600 s) once per account. Answer:

```json
{
  "token": "v1.<base64url>",
  "expires_at": "2027-04-15T06:00:00.000Z",
  "user": { "id": "u_0f3c…", "email": "me@example.com" },
  "trial_granted": true
}
```

The token is opaque: keep it in the Keychain, send it as `Authorization: Bearer <token>`. It lives 180 days and
slides: a `200` answer to a token older than 30 days carries a fresh one in `X-Kotoba-Token` (its expiry in
`X-Kotoba-Token-Expires`). Replace the stored token with it. "Sign out everywhere" ends old and fresh tokens alike.

### `POST /v1/transcribe`

The body is the recording, the same FLAC bytes the app sends today (16 kHz mono). Headers the macOS client must send:

| Header | Value |
|---|---|
| `Authorization` | `Bearer <token>` |
| `Content-Type` | `audio/flac` |
| `Content-Length` | Required (`411` without it). The body length; URLSession sets it for a `Data` or file upload. The hold comes from it |
| `X-Kotoba-Audio-Seconds` | Optional hint: the recording length as the app measured it, for example `12.48`. Never used for money |
| `X-Kotoba-Language` | Optional. A language code such as `en`; leave it out for auto-detect |
| `X-Kotoba-Phrases` | Optional. Dictionary terms: base64url (padding optional) of a UTF-8 JSON array of strings; at most 200 terms of 1-100 characters |

Answer `200`:

```json
{
  "text": "Hello there.",
  "billed_seconds": 13,
  "plan": null,
  "seconds_left": 3587,
  "plan_seconds_left": 0,
  "pack_seconds": 3587,
  "plan_period_end": null,
  "plan_resets_at": null
}
```

The balance fields are the balance after this dictation is paid. The payment runs just after the response, so they are
an estimate; `GET /v1/account` has the settled numbers. Update the hours shown in the app from this response; no
polling is needed.

Metering:

1. **Stated length:** STREAMINFO's length, else `X-Kotoba-Audio-Seconds`, rounded up. It only decides whether the
   dictation may start, never what it costs. With neither, the byte bound below is the stated length.
2. **Byte bound:** the most the body can hold, `ceil(Content-Length / MIN_AUDIO_BYTES_PER_SECOND)` seconds (6,000 B/s,
   at least 1, at most `MAX_AUDIO_SECONDS`). The owner's 16 kHz speech recordings run 13-17 KB/s (n = 24), so the
   bound is about 2.5 times the real length.
3. **Authorize:** the dictation starts when the seconds not yet held cover the stated length; else `402`
   (`out_of_hours` at zero, `not_enough_hours` otherwise). It holds the byte bound, at most the free seconds; it
   cuts a hold to the free seconds only when no other dictation of the user is open (else `not_enough_hours`), so
   parallel dictations cannot share one cut hold. This
   runs in parallel with the upload and answers in a few milliseconds, so a refusal reaches the app while it still
   uploads.
4. **Pay:** Azure's own `durationMilliseconds`, rounded up to whole seconds, at most the hold. With no duration from
   Azure, the hold is paid. Plan hours first, then pack hours (oldest pack first). No balance goes below zero. A
   dictation is free only when its payment fails after the response (see "Stubbed").
5. **More audio than the byte bound** (below the bitrate floor: a muted microphone or a crafted file): the user pays
   the hold and gets `bad_audio`, no text.

**Most a lying client can take:** it understates the length, so the dictation starts, and the byte bound is held up to
its whole balance. It pays its whole balance and gets the text of at most one recording past it, at most
`MAX_AUDIO_SECONDS` (1,200 s, about USD 0.033 at USD 0.10/h). Then it is at 0 and gets `out_of_hours`. So the loss is
at most 1,200 s of audio per account per top-up (the free hour counts as one). A file below the bitrate floor gets no
text, so there is nothing to gain from one; what Azure transcribes of it before it answers (Azure takes up to 2 h of
audio a request) is bounded only by the rate limit and the global daily cap, which counts Azure's duration.

**Before upload:** the app compares the recording's length with `seconds_left` from the last response, while it
records (to warn when the balance runs out mid-dictation) and before it uploads. When the recording is longer, it shows
"Out of kotoba Cloud hours" with Buy Hours and Use My Own Key and keeps the recording, with no upload. The server's
`not_enough_hours` is the backstop (for example two dictations at once).

### `GET /v1/account`

`Authorization: Bearer <token>`. Answer `200`:

```json
{
  "user": { "id": "u_0f3c…", "email": "me@example.com" },
  "plan": "pro",
  "seconds_left": 30600,
  "plan_seconds_left": 27000,
  "pack_seconds": 3600,
  "plan_period_end": "2026-11-17T06:00:00.000Z",
  "plan_resets_at": "2026-11-17T06:00:00.000Z"
}
```

`plan` is `"pro"` or `null`. `plan_resets_at` is when the monthly plan hours reset (each month of an annual plan too).
Ask at sign-in and when the app becomes active after a checkout, not on a timer.

### `POST /v1/sign-out-everywhere`

`Authorization: Bearer <token>`. Answer `204`. Every token of the user stops working on its next request, this one
too. A token that is already ended gets `401`.

### `POST /v1/cleanup`

Not built. Answer `501 not_implemented`.

### `POST /billing/paddle`

Paddle Billing notifications only. The `Paddle-Signature` header (`ts=…;h1=…`, HMAC-SHA256 of `ts:raw body` with the
notification secret) must match and `ts` must be within `PADDLE_TOLERANCE_SECONDS` (5 s, as Paddle's SDKs do). Answer
`200 {"ok": true, "outcome": "<what it did>"}` for every verified event, also one it cannot place, so Paddle stops
retrying; `401 bad_signature` otherwise. One exception: a refund for a purchase not yet recorded (Paddle does not keep
the order) gets `409 {"ok": false, "outcome": "no_purchase"}`, so Paddle sends it again.

The checkout (a web page, not built) must pass `customData: {"kotoba_user_id": "<user id>"}` to `Paddle.Checkout.open()`.
Paddle copies it to the transaction and to the subscription. `PADDLE_PRICES` in `wrangler.jsonc` maps each Paddle price
id to what it sells (INR prices are overrides on the same ids):

| Event | Effect |
|---|---|
| `transaction.completed`, pack price | Adds `seconds x quantity` pack seconds, once per transaction and price |
| `transaction.completed`, Pro price | Starts the paid period from `billing_period` with 8 h for each month of it; each renewal does this again. An older period of the same subscription changes nothing |
| `subscription.created` / `updated` / `paused` / `resumed` / `canceled` | Kept in D1; an event older than the stored one changes nothing |
| Any of those with status `paused` or `canceled` | Ends that subscription's plan hours now; pack hours stay. After a cancel, no late period of that subscription can start. A resume brings no hours back; the next `transaction.completed` does |
| `adjustment.created` / `updated`, an approved `refund` or `chargeback` of a pack | Takes back the refunded share of that pack's seconds (all of them for a full refund), only from what is left of that pack, never below zero; used hours are not a debt. The user comes from `purchases` (adjustments carry no `custom_data`) |

A cancel at the period end keeps the hours: Paddle sends `subscription.canceled` on the date it takes effect.

## Abuse limits

- Per user: 30 dictations a minute (Workers rate limiting binding, `TRANSCRIBE_LIMITER`).
- Per client IP: 10 sign-in calls a minute (`AUTH_LIMITER`); per email: one code each 30 s, 5 wrong tries per code,
  and a new code keeps the tries count.
- Per request: at most 32 MiB and 1,200 s of audio; `Content-Length` is required, and the relay stops a body that
  sends more. A STREAMINFO or header length over 1,200 s is refused early (claims can refuse, never discount).
- All users: `GLOBAL_DAILY_CAP_SECONDS` a UTC day (200 h, about USD 20 at USD 0.10/h). Each dictation reserves its
  hold at the gate; a refused or failed one gives it back, and a paid one is corrected to Azure's duration. Past the
  cap, every dictation gets `service_paused`.
- The relay sets the model (`MAI-Transcribe-2`); no client can pick a costlier one.
- Logs hold user id, seconds and outcome only: no audio, no text.

## Latency

Rule: the relay must not move dictation latency (gate: stop tap to Cmd-V p50 <= 1.0 s, p90 <= 1.5 s). The balance
check, the daily cap and the rate limit run in parallel with the upstream request, and the payment runs after the
response. So on the critical path the relay adds one hop, the token check (AES-GCM, no storage read) and the streamed
multipart.

Measured locally on 2026-10-17 at 03:05 IST (after the billing fixes), Apple M3 Pro, `bun run latency 200`: 200 pairs per size after 20 warm-up
pairs, each pair the same dictation sent straight to the fake Azure and through `wrangler dev` (the real
`AzureTranscriber`) to the same fake Azure, in alternating order. Overhead is the paired difference, in ms:

| Audio | Body | Direct p50 / p90 | Relay p50 / p90 | **Overhead p50 / p90** |
|---|---|---|---|---|
| 2 s | 36 KB | 0.1 / 0.2 | 3.0 / 3.6 | **2.9 / 3.5** |
| 10 s | 180 KB | 0.2 / 0.2 | 3.5 / 4.9 | **3.3 / 4.7** |
| 30 s | 540 KB | 0.2 / 0.4 | 5.1 / 6.8 | **4.8 / 6.6** |

This is the relay's own CPU and local-hop cost in workerd, with no network. It is not the production number.

Measure before launch (paired with the BYOK route, n >= 50, from an Indian home network, against the gate):

1. Stop tap to Cmd-V through the deployed relay vs BYOK OpenRouter: p50 and p90. The headroom today is about 100 ms
   (bench round trip p50 902 ms).
2. Edge to Azure `centralindia` from the Worker: TCP, TLS and time to first byte. Check the Worker runs in BOM
   (`cf-ray`) and that the subrequest reuses its connection.
3. Where the Balance and GlobalMeter Durable Objects live for Indian users (`cf-ray` of a DO request, or a probe). If
   they live outside India the gates take one long round trip; they must still finish before Azure answers.
4. Azure MAI-Transcribe-2 time with a phrase list of 200 terms vs none.
5. Upload: chunked vs `Content-Length` to Azure, and a 10-minute recording on a slow uplink against the 120 s timeout.
6. Cold start of the Worker (first request after idle) and the first request of a new isolate (key import).
7. The first dictation after sign-in (Durable Object creation).

Do before launch (billing and abuse):

1. Re-measure `MIN_AUDIO_BYTES_PER_SECOND` on more microphones and rooms (built-in, AirPods, USB, quiet and noisy).
   Today's 6,000 B/s rests on 24 recordings from one Mac (13-17 KB/s). A real recording below the floor gets
   `bad_audio`.
2. A FLAC frame reader in the relay stream: cut the upload at `MAX_AUDIO_SECONDS` of frames, so a crafted
   low-bitrate file cannot make Azure transcribe more than 1,200 s. The STREAMINFO format check (16 kHz mono 16-bit)
   only makes such a file lie about less.

## Stubbed or not built

- The email sender: `ConsoleMailer` prints the code. A real mailer (Resend in the proposal) is not written.
- The Paddle checkout page and the customer portal link; the `customData` contract is above.
- `/v1/cleanup` (Gemini through the relay).
- Real Azure: `AzureTranscriber` is written to Microsoft's REST reference and tested against a fake fetch and the local
  stand-in, never against Azure.
- Pro refunds (Paddle's own subscription events end the plan) and `transaction.payment_failed`: ignored.
- A retry when `settle` fails after a response: the hold lapses after 10 minutes and that dictation is free.
- Aborting the upstream request when the client goes away (needs the `enable_request_signal` flag).
- Deploy config: real D1 id, custom domain, secrets (`wrangler secret put`), spend alarms on Azure.

## Unresolved questions

None open. The owner's decisions so far: holds and refunds as above; the frame reader and the bitrate floor are
pre-launch items ("Do before launch").
