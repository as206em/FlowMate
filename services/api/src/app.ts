import { sql } from "drizzle-orm";
import { Hono } from "hono";
import { compress } from "hono/compress";
import { logger } from "hono/logger";
import { requireToken } from "./auth.js";
import type { Db } from "./db/client.js";
import { meRoutes } from "./routes/me.js";
import { snapshotRoutes } from "./routes/snapshots.js";

export function createApp(db: Db, options: { log?: boolean } = {}) {
  const app = new Hono();
  // Method, path and status only: never headers, so tokens stay out of the logs
  if (options.log) app.use(logger());

  app.get("/health/live", (c) => c.json({ ok: true }));
  app.get("/health/ready", async (c) => {
    try {
      await db.execute(sql`select 1`);
      return c.json({ ok: true });
    } catch {
      return c.json({ ok: false }, 503);
    }
  });

  const v1 = new Hono();
  v1.use(compress());
  v1.use(requireToken(db));
  v1.route("/me", meRoutes(db));
  v1.route("/workspaces", snapshotRoutes(db));
  app.route("/v1", v1);

  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.onError((err, c) => {
    console.error(err);
    return c.json({ error: "internal" }, 500);
  });
  return app;
}
