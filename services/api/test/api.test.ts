import { eq } from "drizzle-orm";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createUserWithWorkspace, issueToken, revokeToken } from "../src/accounts.js";
import { users, workspaceMembers, workspaceSnapshotHistory } from "../src/db/schema.js";
import { HISTORY_KEEP } from "../src/routes/snapshots.js";
import { setup } from "./helpers.js";

type Env = Awaited<ReturnType<typeof setup>>;
let env: Env;
let owner: Awaited<ReturnType<typeof createUserWithWorkspace>>;

const sample = (title: string) => ({
  schemaVersion: 14,
  projects: [{ id: "6F1C2E0A-0000-4000-8000-000000000001", name: "Inbox" }],
  tasks: [{ id: "6F1C2E0A-0000-4000-8000-000000000002", title, spentSeconds: 1.5 }],
  runningTimers: ["6F1C2E0A-0000-4000-8000-000000000002", 784000000.25],
});

const put = (body: object, token = owner.token.token, ws = owner.workspace.id) =>
  env.call(`/v1/workspaces/${ws}/snapshot`, { method: "PUT", token, json: body });
const get = (token = owner.token.token, ws = owner.workspace.id, headers?: HeadersInit) =>
  env.call(`/v1/workspaces/${ws}/snapshot`, { token, headers });

beforeEach(async () => {
  env = await setup();
  owner = await createUserWithWorkspace(env.db, { displayName: "Asem", email: "Me@Example.com", tokenName: "MacBook" });
});
afterEach(async () => env.close());

describe("health", () => {
  it("live and ready answer without a token", async () => {
    expect((await env.call("/health/live")).status).toBe(200);
    expect(await (await env.call("/health/ready")).json()).toEqual({ ok: true });
  });
});

describe("auth", () => {
  it("rejects a missing, wrong or revoked token", async () => {
    expect((await env.call("/v1/me")).status).toBe(401);
    expect((await env.call("/v1/me", { token: "fm_nope" })).status).toBe(401);
    await revokeToken(env.db, owner.token.id);
    const res = await env.call("/v1/me", { token: owner.token.token });
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ error: "unauthorized" });
  });

  it("stores only a hash of the token and the email lower-cased", async () => {
    const [user] = await env.db.select().from(users);
    expect(user!.email).toBe("me@example.com");
    expect(owner.token.token).toMatch(/^fm_[A-Za-z0-9_-]{43}$/);
  });
});

describe("GET /v1/me", () => {
  it("lists the user's workspaces with their snapshot version", async () => {
    let me = await (await env.call("/v1/me", { token: owner.token.token })).json();
    expect(me).toEqual({
      user: { id: owner.user.id, email: "me@example.com", displayName: "Asem" },
      workspaces: [{ id: owner.workspace.id, name: "My workspace", role: "owner", snapshotVersion: null }],
    });
    await put({ baseVersion: 0, schemaVersion: 14, data: sample("a") });
    me = await (await env.call("/v1/me", { token: owner.token.token })).json();
    expect(me.workspaces[0].snapshotVersion).toBe(1);
  });
});

describe("snapshots", () => {
  it("404 no_snapshot before the first push", async () => {
    const res = await get();
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: "no_snapshot" });
  });

  it("first push creates version 1 and round-trips the data", async () => {
    const res = await put({ baseVersion: 0, schemaVersion: 14, deviceName: "MacBook", data: sample("Write spec") });
    expect(res.status).toBe(200);
    const saved = await res.json();
    expect(saved.version).toBe(1);

    const got = await get();
    expect(got.status).toBe(200);
    expect(got.headers.get("etag")).toBe('"1"');
    const body = await got.json();
    expect(body).toMatchObject({ version: 1, schemaVersion: 14, updatedByDevice: "MacBook", updatedAt: saved.updatedAt });
    expect(body.data).toEqual(sample("Write spec"));
  });

  it("304 when the client already has that version", async () => {
    await put({ baseVersion: 0, schemaVersion: 14, data: sample("a") });
    expect((await get(undefined, undefined, { "if-none-match": '"1"' })).status).toBe(304);
    expect((await get(undefined, undefined, { "if-none-match": 'W/"1"' })).status).toBe(304);
    expect((await get(undefined, undefined, { "if-none-match": 'W/"2"' })).status).toBe(200);
  });

  it("each push based on the current version bumps it", async () => {
    await put({ baseVersion: 0, schemaVersion: 14, data: sample("a") });
    const res = await put({ baseVersion: 1, schemaVersion: 14, data: sample("b") });
    expect((await res.json()).version).toBe(2);
    expect((await (await get()).json()).data.tasks[0].title).toBe("b");
  });

  it("409 when the base version is stale, and nothing changes", async () => {
    await put({ baseVersion: 0, schemaVersion: 14, deviceName: "MacBook", data: sample("a") });
    await put({ baseVersion: 1, schemaVersion: 14, deviceName: "MacBook", data: sample("b") });
    const res = await put({ baseVersion: 1, schemaVersion: 14, deviceName: "iMac", data: sample("stale") });
    expect(res.status).toBe(409);
    expect(await res.json()).toMatchObject({ error: "version_conflict", currentVersion: 2, updatedByDevice: "MacBook" });
    expect((await (await get()).json()).data.tasks[0].title).toBe("b");
  });

  it("409 for a first push when the cloud already has data", async () => {
    await put({ baseVersion: 0, schemaVersion: 14, data: sample("a") });
    const res = await put({ baseVersion: 0, schemaVersion: 14, data: sample("other mac") });
    expect(res.status).toBe(409);
    expect((await res.json()).currentVersion).toBe(1);
  });

  it("force overwrites whatever is there", async () => {
    await put({ baseVersion: 0, schemaVersion: 14, data: sample("a") });
    const res = await put({ baseVersion: 0, force: true, schemaVersion: 14, data: sample("mine") });
    expect(res.status).toBe(200);
    expect((await res.json()).version).toBe(2);
    expect((await (await get()).json()).data.tasks[0].title).toBe("mine");
  });

  it("keeps earlier versions, only the newest few", async () => {
    let v = 0;
    for (let i = 0; i < HISTORY_KEEP + 5; i++) {
      v = (await (await put({ baseVersion: v, schemaVersion: 14, data: sample(`t${i}`) })).json()).version;
    }
    const history = await env.db.select().from(workspaceSnapshotHistory);
    expect(history).toHaveLength(HISTORY_KEEP);
    const versions = history.map((h) => h.version).sort((a, b) => a - b);
    expect(versions.at(-1)).toBe(v - 1);
    expect(versions[0]).toBe(v - HISTORY_KEEP);
  });

  it("rejects bad bodies", async () => {
    expect((await put({ baseVersion: -1, schemaVersion: 14, data: {} })).status).toBe(400);
    expect((await put({ baseVersion: 0, schemaVersion: 14, data: [1, 2] })).status).toBe(400);
    const raw = await env.call(`/v1/workspaces/${owner.workspace.id}/snapshot`, {
      method: "PUT",
      token: owner.token.token,
      headers: { "content-type": "application/json" },
      body: "{not json",
    });
    expect(raw.status).toBe(400);
  });

  it("413 for a document over the size limit", async () => {
    const huge = { blob: "x".repeat(26 * 1024 * 1024) };
    const res = await put({ baseVersion: 0, schemaVersion: 14, data: huge });
    expect(res.status).toBe(413);
  });
});

describe("access", () => {
  it("someone else's workspace reads as not found", async () => {
    const other = await createUserWithWorkspace(env.db, { displayName: "Other" });
    expect((await get(other.token.token)).status).toBe(404);
    expect((await put({ baseVersion: 0, schemaVersion: 14, data: {} }, other.token.token)).status).toBe(404);
    expect((await get(owner.token.token, "not-a-uuid")).status).toBe(404);
  });

  it("a viewer can read but not write", async () => {
    await put({ baseVersion: 0, schemaVersion: 14, data: sample("a") });
    const viewer = await createUserWithWorkspace(env.db, { displayName: "Viewer" });
    await env.db
      .insert(workspaceMembers)
      .values({ workspaceId: owner.workspace.id, userId: viewer.user.id, role: "viewer" });
    expect((await get(viewer.token.token)).status).toBe(200);
    const res = await put({ baseVersion: 1, schemaVersion: 14, data: sample("b") }, viewer.token.token);
    expect(res.status).toBe(403);
  });

  it("a second device token of the same user shares the workspace", async () => {
    const second = await issueToken(env.db, owner.user.id, "iMac");
    await put({ baseVersion: 0, schemaVersion: 14, data: sample("from macbook") });
    expect((await (await get(second.token)).json()).data.tasks[0].title).toBe("from macbook");
    const [u] = await env.db.select().from(users).where(eq(users.id, owner.user.id));
    expect(u).toBeDefined();
  });
});
