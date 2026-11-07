import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";
import { createApp } from "../src/app.js";
import { schema, type Db } from "../src/db/client.js";

/** A fresh in-process Postgres (PGlite) with the real migrations applied, and the app on top. */
export async function setup() {
  const pg = new PGlite();
  const pgDb = drizzle(pg, { schema });
  await migrate(pgDb, { migrationsFolder: new URL("../drizzle", import.meta.url).pathname });
  const db = pgDb as unknown as Db;
  const app = createApp(db);
  const call = (path: string, init: RequestInit & { token?: string; json?: unknown } = {}) => {
    const headers = new Headers(init.headers);
    if (init.token) headers.set("authorization", `Bearer ${init.token}`);
    let body = init.body;
    if (init.json !== undefined) {
      headers.set("content-type", "application/json");
      body = JSON.stringify(init.json);
    }
    return app.request(path, { ...init, headers, body });
  };
  return { pg, db, app, call, close: () => pg.close() };
}
