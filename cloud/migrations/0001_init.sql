-- kotoba Cloud: accounts and purchases. Hours live in each user's Balance Durable Object, not here.
-- Times are Unix ms, except paddle_events.occurred_at (Paddle's ISO string).

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  trial_granted_at INTEGER
);

-- One pending sign-in code per email, as an HMAC (never the code itself).
CREATE TABLE auth_codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  sent_at INTEGER NOT NULL
);
CREATE INDEX auth_codes_expires ON auth_codes (expires_at);

CREATE TABLE purchases (
  paddle_txn_id TEXT NOT NULL,
  price_id TEXT NOT NULL,
  -- Paddle's transaction line item (txnitm_) and its total in the currency's smallest unit: refunds name the line
  -- item, and a partial refund takes back the same share of seconds as of this total.
  line_item_id TEXT,
  amount_total TEXT,
  user_id TEXT NOT NULL REFERENCES users (id),
  kind TEXT NOT NULL CHECK (kind IN ('pack', 'pro')),
  seconds_granted INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (paddle_txn_id, price_id)
);
CREATE INDEX purchases_user ON purchases (user_id);

CREATE TABLE subscriptions (
  paddle_sub_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id),
  price_id TEXT,
  status TEXT NOT NULL,
  period_end INTEGER,
  -- occurred_at of the newest event applied; Paddle can deliver events out of order.
  event_at INTEGER NOT NULL
);
CREATE INDEX subscriptions_user ON subscriptions (user_id);

CREATE TABLE paddle_events (
  event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  outcome TEXT NOT NULL,
  received_at INTEGER NOT NULL
);
