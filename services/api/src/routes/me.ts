import { eq } from "drizzle-orm";
import { Hono } from "hono";
import type { MeResponse } from "@flowmate/api-contract";
import type { AuthVars } from "../auth.js";
import type { Db } from "../db/client.js";
import { users, workspaceMembers, workspaces, workspaceSnapshots } from "../db/schema.js";

export function meRoutes(db: Db) {
  const app = new Hono<{ Variables: AuthVars }>();
  app.get("/", async (c) => {
    const userId = c.get("userId");
    const [user] = await db.select().from(users).where(eq(users.id, userId));
    if (!user) return c.json({ error: "unauthorized" }, 401);
    const rows = await db
      .select({
        id: workspaces.id,
        name: workspaces.name,
        role: workspaceMembers.role,
        snapshotVersion: workspaceSnapshots.version,
        createdAt: workspaces.createdAt,
      })
      .from(workspaceMembers)
      .innerJoin(workspaces, eq(workspaces.id, workspaceMembers.workspaceId))
      .leftJoin(workspaceSnapshots, eq(workspaceSnapshots.workspaceId, workspaces.id))
      .where(eq(workspaceMembers.userId, userId))
      .orderBy(workspaces.createdAt);
    const body: MeResponse = {
      user: { id: user.id, email: user.email, displayName: user.displayName },
      workspaces: rows.map(({ createdAt: _, ...w }) => ({ ...w, snapshotVersion: w.snapshotVersion ?? null })),
    };
    return c.json(body);
  });
  return app;
}
