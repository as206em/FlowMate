import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { loadConfig } from "./config.js";
import { connect, runMigrations } from "./db/postgres.js";

const config = loadConfig();
const { client, db } = connect(config.databaseUrl);
await runMigrations(client, config.migrationsDir);

const server = serve({ fetch: createApp(db, { log: true }).fetch, port: config.port }, (info) => {
  console.log(`FlowMate API listening on :${info.port}`);
});

async function shutdown() {
  server.close();
  await client.end({ timeout: 5 });
  process.exit(0);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
