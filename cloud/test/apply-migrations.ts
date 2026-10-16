import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

// Runs before each test file; only migrations not yet applied run.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
