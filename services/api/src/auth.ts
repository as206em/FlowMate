import { and, eq, isNull } from "drizzle-orm";
import { createMiddleware } from "hono/factory";
import type { Db } from "./db/client.js";
import { apiTokens } from "./db/schema.js";
import { hashToken } from "./accounts.js";

export type AuthVars = { userId: string };

// last_used_at is only written when it's this old, so reads don't turn into writes
const LAST_USED_RESOLUTION_MS = 5 * 60 * 1000;

/** Requires `Authorization: Bearer <token>` with a token that isn't revoked. */
export function requireToken(db: Db) {
  return createMiddleware<{ Variables: AuthVars }>(async (c, next) => {
    const header = c.req.header("authorization") ?? "";
    const match = /^Bearer\s+(\S+)$/i.exec(header);
    if (!match) return c.json({ error: "unauthorized" }, 401);
    const [token] = await db
      .select({ id: apiTokens.id, userId: apiTokens.userId, lastUsedAt: apiTokens.lastUsedAt })
      .from(apiTokens)
      .where(and(eq(apiTokens.tokenHash, hashToken(match[1]!)), isNull(apiTokens.revokedAt)));
    if (!token) return c.json({ error: "unauthorized" }, 401);
    if (!token.lastUsedAt || Date.now() - token.lastUsedAt.getTime() > LAST_USED_RESOLUTION_MS) {
      await db.update(apiTokens).set({ lastUsedAt: new Date() }).where(eq(apiTokens.id, token.id));
    }
    c.set("userId", token.userId);
    await next();
  });
}
