import { cpSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const sourceUiDir = resolve(root, "packages/plugin/ui");
const pluginRoot = resolve(root, "packages/plugin/com.descript.streamdeck.sdPlugin");
const targetUiDir = resolve(pluginRoot, "ui");
const categoryIcon = resolve(pluginRoot, "assets/actions/category.svg");

mkdirSync(targetUiDir, { recursive: true });
cpSync(sourceUiDir, targetUiDir, { recursive: true });

execFileSync("sips", [
  "-z",
  "256",
  "256",
  "-s",
  "format",
  "png",
  categoryIcon,
  "--out",
  resolve(pluginRoot, "assets/plugin-icon.png")
]);

execFileSync("sips", [
  "-z",
  "512",
  "512",
  "-s",
  "format",
  "png",
  categoryIcon,
  "--out",
  resolve(pluginRoot, "assets/plugin-icon@2x.png")
]);

console.log(`Synced plugin UI and icon assets into ${pluginRoot}`);

