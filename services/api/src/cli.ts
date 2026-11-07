import { parseArgs } from "node:util";
import { desc, eq } from "drizzle-orm";
import { createUserWithWorkspace, findUser, issueToken, revokeToken } from "./accounts.js";
import { loadConfig } from "./config.js";
import { apiTokens } from "./db/schema.js";
import { connect, runMigrations } from "./db/postgres.js";

const HELP = `FlowMate API admin

  create-user  --name <name> [--email <email>] [--workspace <name>] [--device <token name>]
               A user, their workspace and a first token (printed once).
  create-token --user <id|email> --device <name>   Another token, e.g. for a second Mac.
  list-tokens  --user <id|email>
  revoke-token --id <token id>

In the cluster:  docker exec -it $(docker ps -qf name=flowmate_api) node dist/cli.js <command> ...`;

const [command, ...rest] = process.argv.slice(2);
const { values } = parseArgs({
  args: rest,
  options: {
    name: { type: "string" },
    email: { type: "string" },
    workspace: { type: "string" },
    device: { type: "string" },
    user: { type: "string" },
    id: { type: "string" },
  },
});

if (!command || command === "help" || command === "--help") {
  console.log(HELP);
  process.exit(0);
}

const config = loadConfig();
const { client, db } = connect(config.databaseUrl);
await runMigrations(client, config.migrationsDir);

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

try {
  switch (command) {
    case "create-user": {
      if (!values.name) fail("--name is required");
      const r = await createUserWithWorkspace(db, {
        displayName: values.name,
        email: values.email,
        workspaceName: values.workspace,
        tokenName: values.device,
      });
      console.log(`User       ${r.user.id}`);
      console.log(`Workspace  ${r.workspace.id} (${r.workspace.name})`);
      console.log(`Token      ${r.token.token}`);
      console.log("\nPaste the token into FlowMate › Settings › Cloud Sync. It isn't shown again.");
      break;
    }
    case "create-token": {
      const user = values.user ? await findUser(db, values.user) : undefined;
      if (!user) fail("User not found (--user <id|email>)");
      const t = await issueToken(db, user.id, values.device ?? "Device");
      console.log(`Token ${t.id} (${t.name})\n${t.token}`);
      break;
    }
    case "list-tokens": {
      const user = values.user ? await findUser(db, values.user) : undefined;
      if (!user) fail("User not found (--user <id|email>)");
      const tokens = await db.select().from(apiTokens).where(eq(apiTokens.userId, user.id)).orderBy(desc(apiTokens.createdAt));
      for (const t of tokens) {
        const state = t.revokedAt ? "revoked" : `last used ${t.lastUsedAt?.toISOString() ?? "never"}`;
        console.log(`${t.id}  ${t.name}  ${state}`);
      }
      break;
    }
    case "revoke-token": {
      if (!values.id) fail("--id is required");
      console.log((await revokeToken(db, values.id)) ? "Revoked" : "No active token with that id");
      break;
    }
    default:
      fail(`Unknown command "${command}"\n\n${HELP}`);
  }
} finally {
  await client.end({ timeout: 5 });
}
