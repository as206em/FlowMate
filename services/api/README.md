# FlowMate API

Stores each account's workspace so FlowMate can keep a copy in the cloud, and later open the same account on several devices and share it with a team.

**Phase 1 (now):** the whole workspace is one JSON document, the same one the Mac app keeps in `workspace.json`. Every write names the version it was based on, so a device that is behind gets a `409` instead of overwriting newer data. The 30 versions before the current one are kept in `workspace_snapshot_history` for recovery by hand. Users, workspaces, members with roles and per-device tokens are already in the schema, so login and sharing can come without reshaping the data.

**Later:** email or Sign in with Apple, invites and roles, and per-record tables (projects, tasks, time entries) so several people and devices can edit at the same time and merge.

## API (v1)

Every `/v1` call sends `Authorization: Bearer fm_…`. The shapes are in [`packages/api-contract`](../../packages/api-contract/src/index.ts).

| Call | Answer |
|---|---|
| `GET /health/live`, `GET /health/ready` | `{"ok":true}` (ready also checks the database) |
| `GET /v1/me` | the user and their workspaces, each with its role and `snapshotVersion` |
| `GET /v1/workspaces/:id/snapshot` | `{version, schemaVersion, updatedAt, updatedByDevice, data}`, `404 no_snapshot` before the first push. Sends an `ETag`, so `If-None-Match` gets `304`. |
| `PUT /v1/workspaces/:id/snapshot` | body `{baseVersion, schemaVersion, deviceName, force?, data}` returns `{version, updatedAt}`, or `409 version_conflict` with the current version. `baseVersion` is 0 for the first push. `force` overwrites. Viewers get `403`. Limit 25 MB. |

Someone else's workspace answers `404`, the same as one that doesn't exist.

## Run it locally

With Docker, from the repository root:

```bash
docker compose -f docker-compose.dev.yml up --build
docker compose -f docker-compose.dev.yml exec api node dist/cli.js create-user --name Me
```

Without Docker (the `embedded-postgres` package brings a real Postgres):

```bash
pnpm tsx test/local-postgres.ts          # terminal 1: Postgres on 127.0.0.1:55432
export DATABASE_URL=postgres://flowmate:flowmate@127.0.0.1:55432/flowmate
pnpm dev                                 # terminal 2: API on http://localhost:8080
pnpm cli create-user --name Me --device "MacBook"
```

Paste the token into FlowMate › Settings › Cloud sync, with server `http://localhost:8080`.

## Admin CLI

There is no sign-up yet: accounts and tokens are made with the CLI (`pnpm cli …` locally, `node dist/cli.js …` in the container).

```
create-user  --name <name> [--email <email>] [--workspace <name>] [--device <token name>]
create-token --user <id|email> --device <name>     another device
list-tokens  --user <id|email>
revoke-token --id <token id>
```

Only a SHA-256 hash of each token is stored, so a token is shown once when it's made.

## Settings

| Variable | |
|---|---|
| `DATABASE_URL` | `postgres://user@host:5432/db` |
| `DATABASE_PASSWORD_FILE` | file holding the database password (a Docker secret), instead of putting it in the URL |
| `PORT` | default 8080 |

Migrations (`drizzle/`) run on start. After changing `src/db/schema.ts`, run `pnpm db:generate` and commit the new SQL file.

## Tests

`pnpm test` runs the API against PGlite (Postgres in WebAssembly) with the real migrations, so no database is needed. The Mac app has a matching end-to-end test against a running API:

```bash
cd apps/macos
FLOWMATE_LIVE_API_URL=http://127.0.0.1:8080 FLOWMATE_LIVE_API_TOKEN=fm_… swift test --filter CloudSyncLiveTests
```

Use a separate user for it, since it writes to that user's workspace.
