# FlowMate API. Build from the repository root (it needs the workspace files):
#   docker build -f services/api/Dockerfile -t flowmate-api .

FROM node:22-alpine AS build
WORKDIR /repo
RUN corepack enable
# Dependencies first, so code changes don't reinstall them
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/api-contract/package.json packages/api-contract/
COPY services/api/package.json services/api/
RUN pnpm install --frozen-lockfile --filter "@flowmate/api..."
COPY tsconfig.base.json ./
COPY packages/api-contract packages/api-contract
COPY services/api services/api
RUN pnpm --filter @flowmate/api build

# The bundle carries its dependencies: only dist/ and the migrations are needed
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8080 NO_COLOR=1
COPY --from=build /repo/services/api/dist ./dist
COPY --from=build /repo/services/api/drizzle ./drizzle
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health/live > /dev/null || exit 1
CMD ["node", "--enable-source-maps", "dist/server.js"]
