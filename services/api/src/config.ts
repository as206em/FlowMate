import { readFileSync } from "node:fs";

export interface Config {
  port: number;
  databaseUrl: string;
  migrationsDir: string;
}

/**
 * Reads settings from the environment.
 * - DATABASE_URL: postgres://user@host:5432/db (the password may be left out and given as a file)
 * - DATABASE_PASSWORD_FILE: file holding the password, e.g. a Docker secret in /run/secrets
 * - PORT: default 8080
 * - MIGRATIONS_DIR: default ./drizzle next to dist/
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const raw = env.DATABASE_URL;
  if (!raw) throw new Error("DATABASE_URL is not set");
  const url = new URL(raw);
  if (env.DATABASE_PASSWORD_FILE) {
    url.password = encodeURIComponent(readFileSync(env.DATABASE_PASSWORD_FILE, "utf8").trim());
  }
  return {
    port: Number(env.PORT ?? 8080),
    databaseUrl: url.toString(),
    migrationsDir: env.MIGRATIONS_DIR ?? new URL("../drizzle", import.meta.url).pathname,
  };
}
