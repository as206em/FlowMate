import { and, eq, lte, sql } from "drizzle-orm";
import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { MAX_SNAPSHOT_BYTES, PutSnapshotRequest, type SnapshotResponse } from "@flowmate/api-contract";
import type { AuthVars } from "../auth.js";
import type { Db } from "../db/client.js";
import { workspaceMembers, workspaces, workspaceSnapshotHistory, workspaceSnapshots } from "../db/schema.js";

/** How many earlier versions are kept per workspace */
export const HISTORY_KEEP = 30;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function roleFor(db: Db, workspaceId: string, userId: string) {
  if (!UUID.test(workspaceId)) return undefined;
  const [member] = await db
    .select({ role: workspaceMembers.role })
    .from(workspaceMembers)
    .where(and(eq(workspaceMembers.workspaceId, workspaceId), eq(workspaceMembers.userId, userId)));
  return member?.role;
}

export function snapshotRoutes(db: Db) {
  const app = new Hono<{ Variables: AuthVars }>();

  app.get("/:id/snapshot", async (c) => {
    const id = c.req.param("id");
    // Not a member reads the same as not there
    if (!(await roleFor(db, id, c.get("userId")))) return c.json({ error: "not_found" }, 404);
    const [row] = await db.select().from(workspaceSnapshots).where(eq(workspaceSnapshots.workspaceId, id));
    if (!row) return c.json({ error: "no_snapshot" }, 404);

    const etag = `"${row.version}"`;
    c.header("ETag", etag);
    // Compression turns the ETag weak (W/"3"), so compare without the W/
    const seen = (c.req.header("if-none-match") ?? "").split(",").map((t) => t.trim().replace(/^W\//, ""));
    if (seen.includes(etag)) return c.body(null, 304);
    const body: SnapshotResponse = {
      version: row.version,
      schemaVersion: row.schemaVersion,
      updatedAt: row.updatedAt.toISOString(),
      updatedByDevice: row.updatedByDevice,
      data: row.data as Record<string, unknown>,
    };
    return c.json(body);
  });

  app.put(
    "/:id/snapshot",
    bodyLimit({
      // The document plus room for the small envelope around it
      maxSize: MAX_SNAPSHOT_BYTES + 64 * 1024,
      onError: (c) => c.json({ error: "too_large" }, 413),
    }),
    async (c) => {
      const id = c.req.param("id");
      const userId = c.get("userId");
      const role = await roleFor(db, id, userId);
      if (!role) return c.json({ error: "not_found" }, 404);
      if (role === "viewer") return c.json({ error: "forbidden" }, 403);

      let json: unknown;
      try {
        json = await c.req.json();
      } catch {
        return c.json({ error: "invalid_request", message: "Body is not JSON" }, 400);
      }
      const parsed = PutSnapshotRequest.safeParse(json);
      if (!parsed.success) {
        return c.json({ error: "invalid_request", message: parsed.error.issues[0]?.message }, 400);
      }
      const input = parsed.data;

      const result = await db.transaction(async (tx) => {
        // One writer per workspace at a time
        await tx.select({ id: workspaces.id }).from(workspaces).where(eq(workspaces.id, id)).for("update");
        const [current] = await tx.select().from(workspaceSnapshots).where(eq(workspaceSnapshots.workspaceId, id));
        const currentVersion = current?.version ?? 0;

        if (!input.force && input.baseVersion !== currentVersion) {
          return {
            conflict: {
              error: "version_conflict" as const,
              currentVersion,
              updatedAt: (current?.updatedAt ?? new Date(0)).toISOString(),
              updatedByDevice: current?.updatedByDevice ?? null,
            },
          };
        }

        const version = currentVersion + 1;
        const now = new Date();
        const values = {
          version,
          schemaVersion: input.schemaVersion,
          data: input.data,
          updatedAt: now,
          updatedByUserId: userId,
          updatedByDevice: input.deviceName ?? null,
        };
        if (current) {
          await tx.insert(workspaceSnapshotHistory).values({
            workspaceId: id,
            version: current.version,
            schemaVersion: current.schemaVersion,
            data: current.data,
            createdAt: current.updatedAt,
            createdByDevice: current.updatedByDevice,
          });
          await tx
            .delete(workspaceSnapshotHistory)
            .where(
              and(
                eq(workspaceSnapshotHistory.workspaceId, id),
                lte(workspaceSnapshotHistory.version, sql`${version - 1 - HISTORY_KEEP}`),
              ),
            );
          await tx.update(workspaceSnapshots).set(values).where(eq(workspaceSnapshots.workspaceId, id));
        } else {
          await tx.insert(workspaceSnapshots).values({ workspaceId: id, ...values });
        }
        return { saved: { version, updatedAt: now.toISOString() } };
      });

      if ("conflict" in result) return c.json(result.conflict, 409);
      return c.json(result.saved);
    },
  );

  return app;
}
