import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { accountRoutes } from "./account";
import { authRoutes, ConsoleMailer, type Mailer } from "./auth";
import { ApiError, numberVar } from "./errors";
import { paddleRoutes } from "./paddle";
import type { Session } from "./session";
import { transcribeRoutes } from "./transcribe";
import { AzureTranscriber, FakeTranscriber, type Transcriber } from "./upstream";

/** What the routes take from outside the Worker. Tests swap these; the default export builds them from `env`. */
export interface Deps {
  /** Unix ms. */
  now(): number;
  transcriber(env: Env): Transcriber;
  mailer(env: Env): Mailer;
}

export type AppEnv = { Bindings: Env; Variables: { deps: Deps; session: Session } };

// One client per isolate, as the app keeps one URLSession per provider.
let azure: { endpoint: string; key: string; client: AzureTranscriber } | undefined;

export const defaultDeps: Deps = {
  now: () => Date.now(),
  transcriber(env) {
    if (env.UPSTREAM !== "azure") return new FakeTranscriber(numberVar(env, "FAKE_DELAY_MS"));
    if (azure?.endpoint !== env.AZURE_ENDPOINT || azure.key !== env.AZURE_KEY) {
      azure = {
        endpoint: env.AZURE_ENDPOINT,
        key: env.AZURE_KEY,
        client: new AzureTranscriber(env.AZURE_ENDPOINT, env.AZURE_KEY),
      };
    }
    return azure.client;
  },
  mailer(env) {
    // The console mailer prints codes: dev only. No real mailer exists yet, so anywhere else sign-in cannot start.
    if (env.ENVIRONMENT === "dev") return new ConsoleMailer();
    throw new ApiError(500, "mailer_not_configured", "Sign-in is not available yet.");
  },
};

export function makeApp(deps: Deps = defaultDeps) {
  const app = new Hono<AppEnv>();
  app.use(async (c, next) => {
    c.set("deps", deps);
    await next();
  });
  app.route("/auth", authRoutes);
  app.route("/v1", transcribeRoutes);
  app.route("/v1", accountRoutes);
  app.route("/billing", paddleRoutes);
  app.notFound(() => new ApiError(404, "bad_request", "No such route.").toResponse());
  app.onError((err) => {
    if (err instanceof ApiError) return err.toResponse();
    if (err instanceof HTTPException) return err.getResponse();
    console.error("unhandled", err);
    return new ApiError(500, "internal", "Something went wrong.").toResponse();
  });
  return app;
}
