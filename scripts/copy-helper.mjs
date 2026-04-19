import { execFileSync } from "node:child_process";
import { chmodSync, copyFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const source = resolve(root, "packages/helper/.build/release/descript-bridge");
const destinationDir = resolve(
  root,
  "packages/plugin/com.descript.streamdeck.sdPlugin/bin"
);
const destination = resolve(destinationDir, "descript-bridge");

mkdirSync(destinationDir, { recursive: true });
copyFileSync(source, destination);
chmodSync(destination, 0o755);
// Re-sign after copying so macOS will launch the helper from the plugin bundle path.
execFileSync("codesign", ["--force", "--sign", "-", destination], {
  stdio: "inherit"
});

console.log(`Copied helper to ${destination}`);
