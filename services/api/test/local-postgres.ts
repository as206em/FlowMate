// A real Postgres for local runs without Docker (binaries from the embedded-postgres package).
//   pnpm tsx test/local-postgres.ts   →  postgres://flowmate:flowmate@127.0.0.1:55432/flowmate
// Data lives in .local-postgres/ (git-ignored); delete the folder to start over.
import EmbeddedPostgres from "embedded-postgres";
import { existsSync } from "node:fs";

const port = Number(process.env.PG_PORT ?? 55432);
const databaseDir = new URL("../.local-postgres", import.meta.url).pathname;
const pg = new EmbeddedPostgres({ databaseDir, user: "flowmate", password: "flowmate", port, persistent: true });
if (!existsSync(databaseDir)) {
  await pg.initialise();
  await pg.start();
  await pg.createDatabase("flowmate");
} else {
  await pg.start();
}
console.log(`Postgres on postgres://flowmate:flowmate@127.0.0.1:${port}/flowmate`);
const stop = async () => {
  await pg.stop();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
