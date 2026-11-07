import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import type { Db } from "./client.js";
import { schema } from "./client.js";

// Any number; the same one in every copy of the server, so only one migrates at a time
const MIGRATION_LOCK = 4_242_001;

export function connect(databaseUrl: string) {
  const client = postgres(databaseUrl, { max: 10, onnotice: () => {} });
  const db = drizzle(client, { schema }) as unknown as Db;
  return { client, db };
}

export async function runMigrations(client: postgres.Sql, migrationsFolder: string) {
  const lock = await client.reserve();
  try {
    await lock`select pg_advisory_lock(${MIGRATION_LOCK})`;
    await migrate(drizzle(client), { migrationsFolder });
  } finally {
    await lock`select pg_advisory_unlock(${MIGRATION_LOCK})`;
    lock.release();
  }
}
