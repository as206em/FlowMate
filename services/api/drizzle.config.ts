import { defineConfig } from "drizzle-kit";

// `pnpm db:generate` writes a new SQL migration into ./drizzle after schema.ts changes.
// Migrations run on server start (src/db/migrate.ts).
export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
});
