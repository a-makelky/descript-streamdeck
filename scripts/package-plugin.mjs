import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const pluginRoot = resolve(root, "packages/plugin/com.descript.streamdeck.sdPlugin");
const manifest = JSON.parse(
  readFileSync(resolve(pluginRoot, "manifest.json"), "utf8")
);

const safeName = String(manifest.Name)
  .trim()
  .replace(/\s+/g, "-")
  .replace(/[^a-zA-Z0-9-]/g, "");
const outputDir = resolve(root, "dist");
const outputPath = resolve(
  outputDir,
  `${safeName}-${manifest.Version}.streamDeckPlugin`
);

mkdirSync(outputDir, { recursive: true });

execFileSync("ditto", [
  "-c",
  "-k",
  "--sequesterRsrc",
  "--keepParent",
  pluginRoot,
  outputPath
]);

console.log(`Packaged plugin at ${outputPath}`);

