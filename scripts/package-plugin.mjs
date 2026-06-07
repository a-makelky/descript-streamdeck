import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { relative, resolve } from "node:path";

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
const stageRoot = resolve(outputDir, ".package-stage");
const stagedPluginRoot = resolve(stageRoot, "com.descript.streamdeck.sdPlugin");

mkdirSync(outputDir, { recursive: true });
rmSync(outputPath, { force: true });
rmSync(stageRoot, { force: true, recursive: true });
cpSync(pluginRoot, stagedPluginRoot, {
  filter(source) {
    const sourceRelativePath = relative(pluginRoot, source);
    if (!sourceRelativePath) {
      return true;
    }

    const pathParts = sourceRelativePath.split("/");
    return (
      !pathParts.includes("logs") &&
      !pathParts.includes("__MACOSX") &&
      !sourceRelativePath.endsWith(".DS_Store") &&
      !sourceRelativePath.includes("/._")
    );
  },
  recursive: true
});

execFileSync("ditto", [
  "-c",
  "-k",
  "--norsrc",
  "--keepParent",
  stagedPluginRoot,
  outputPath
]);

rmSync(stageRoot, { force: true, recursive: true });

console.log(`Packaged plugin at ${outputPath}`);
