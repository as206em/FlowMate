// Bundles the server and the admin CLI, dependencies included, into dist/. The Docker image then
// only needs dist/ and drizzle/ (the migrations): no node_modules.
import { build } from "esbuild";

await build({
  entryPoints: ["src/server.ts", "src/cli.ts"],
  outdir: "dist",
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  sourcemap: true,
  // Some dependencies still call require(); give the ESM bundle one
  banner: { js: "import { createRequire as __createRequire } from 'node:module'; const require = __createRequire(import.meta.url);" },
});
