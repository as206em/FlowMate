import { createHash, randomBytes } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";
import type { Db } from "./db/client.js";
import { apiTokens, users, workspaceMembers, workspaces } from "./db/schema.js";

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function generateToken(): string {
  return `fm_${randomBytes(32).toString("base64url")}`;
}

/** A user with their own workspace (owner) and a first device token. Used by the CLI. */
export async function createUserWithWorkspace(
  db: Db,
  input: { displayName?: string; email?: string; workspaceName?: string; tokenName?: string },
) {
  return db.transaction(async (tx) => {
    const [user] = await tx
      .insert(users)
      .values({ displayName: input.displayName ?? null, email: input.email?.trim().toLowerCase() ?? null })
      .returning();
    const [workspace] = await tx
      .insert(workspaces)
      .values({ name: input.workspaceName ?? "My workspace" })
      .returning();
    await tx.insert(workspaceMembers).values({ workspaceId: workspace!.id, userId: user!.id, role: "owner" });
    const token = await issueToken(tx as unknown as Db, user!.id, input.tokenName ?? "First device");
    return { user: user!, workspace: workspace!, token };
  });
}

/** Makes a new token for a user. The plain token is returned once and never stored. */
export async function issueToken(db: Db, userId: string, name: string) {
  const token = generateToken();
  const [row] = await db.insert(apiTokens).values({ userId, name, tokenHash: hashToken(token) }).returning();
  return { id: row!.id, name: row!.name, token };
}

export async function revokeToken(db: Db, tokenId: string) {
  const rows = await db
    .update(apiTokens)
    .set({ revokedAt: new Date() })
    .where(and(eq(apiTokens.id, tokenId), isNull(apiTokens.revokedAt)))
    .returning({ id: apiTokens.id });
  return rows.length > 0;
}

export async function findUser(db: Db, idOrEmail: string) {
  const isUuid = /^[0-9a-f-]{36}$/i.test(idOrEmail);
  const [user] = await db
    .select()
    .from(users)
    .where(isUuid ? eq(users.id, idOrEmail) : eq(users.email, idOrEmail.trim().toLowerCase()));
  return user;
}
