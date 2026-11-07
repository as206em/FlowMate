# FlowMate

A task manager and proofreading partner that lives in the macOS menu bar. This repository holds every part of it.

| Path | What | Stack |
|---|---|---|
| [`apps/macos`](apps/macos) | The Mac app ([README](apps/macos/README.md)) | Swift, SwiftUI, SwiftPM |
| [`services/api`](services/api) | Backend: accounts, workspaces, cloud sync ([README](services/api/README.md)) | TypeScript, Hono, Postgres (Drizzle) |
| [`packages/api-contract`](packages/api-contract) | Request and response shapes of the API, shared by the backend and the web apps | TypeScript, zod |
| [`deploy`](deploy) | Portainer stack for the Swarm cluster ([DEPLOY.md](docs/DEPLOY.md)) | Docker Swarm, Traefik |
| [`docs`](docs) | Releasing, deploying, design system, product notes | |

Planned: `apps/web` (web version), `apps/landing` (landing page), `apps/ios`, `apps/android`. The JS/TS workspace (`pnpm-workspace.yaml`) picks up a new folder under `apps/` once it has a `package.json`.

## Getting started

```bash
# Mac app
cd apps/macos && ./build-app.sh

# Backend (Node 22, pnpm via corepack)
corepack enable
pnpm install
pnpm test
```

Running the backend locally is in [services/api/README.md](services/api/README.md).

## Releasing

Actions › **Release** › Run workflow, then tick what to ship: **macos** (signed, notarized app and update feed), **api** (image to ghcr.io, deployed to the cluster) or **all**. See [docs/RELEASING.md](docs/RELEASING.md) and [docs/DEPLOY.md](docs/DEPLOY.md).
