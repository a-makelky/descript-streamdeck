import { spawnSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  writeFileSync
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const distDir = join(rootDir, "dist");
const artifactDir = join(rootDir, "artifacts", "release-check");
const bundleDir = join(
  rootDir,
  "packages",
  "plugin",
  "com.descript.streamdeck.sdPlugin"
);
const manifestPath = join(bundleDir, "manifest.json");
const helperPath = join(bundleDir, "bin", "descript-bridge");
const pluginLogPath = join(bundleDir, "logs", "com.descript.streamdeck.0.log");
const packagedArtifactPath = join(distDir, "Descript-Recorder-0.1.0.streamDeckPlugin");
const installedPluginPath = join(
  homedir(),
  "Library",
  "Application Support",
  "com.elgato.StreamDeck",
  "Plugins",
  "com.descript.streamdeck.sdPlugin"
);
const streamDeckLogPath = join(
  homedir(),
  "Library",
  "Logs",
  "ElgatoStreamDeck",
  "StreamDeck.log"
);
const requiredBundleFiles = [
  "manifest.json",
  "dist/bin/plugin.js",
  "bin/descript-bridge",
  "ui/settings.html",
  "ui/settings.js",
  "assets/actions/record.svg",
  "assets/actions/pause.svg",
  "assets/actions/stop.svg"
];

const skipBuild = process.argv.includes("--skip-build");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const publishedActionIds = Array.isArray(manifest.Actions)
  ? manifest.Actions.map((action) => action.UUID).filter(Boolean)
  : [];
const recordActionPublished = publishedActionIds.includes(
  "com.descript.streamdeck.record"
);

function runCommand(command, args) {
  const result = spawnSync(command, args, {
    cwd: rootDir,
    encoding: "utf8"
  });

  return {
    command: [command, ...args].join(" "),
    ok: result.status === 0,
    exitCode: result.status ?? 1,
    stdout: result.stdout?.trim() ?? "",
    stderr: result.stderr?.trim() ?? ""
  };
}

function readJsonCommand(command, args) {
  const result = runCommand(command, args);
  if (!result.ok) {
    throw new Error(result.stderr || result.stdout || `${command} failed.`);
  }

  return JSON.parse(result.stdout);
}

function tailLines(path, count) {
  if (!existsSync(path)) {
    return [];
  }

  const lines = readFileSync(path, "utf8")
    .split("\n")
    .map((line) => line.trimEnd())
    .filter(Boolean);

  return lines.slice(-count);
}

function detectInstalledPlugin() {
  if (!existsSync(installedPluginPath)) {
    return {
      exists: false,
      isSymlink: false,
      resolvedPath: null
    };
  }

  const stat = lstatSync(installedPluginPath);
  return {
    exists: true,
    isSymlink: stat.isSymbolicLink(),
    resolvedPath: realpathSync(installedPluginPath)
  };
}

function connectedInStreamDeckLog() {
  const lines = tailLines(streamDeckLogPath, 400);
  return lines.some((line) => line.includes("[com.descript.streamdeck] Plugin connected"));
}

function buildBundleEvidence() {
  return requiredBundleFiles.map((relativePath) => ({
    path: relativePath,
    exists: existsSync(join(bundleDir, relativePath))
  }));
}

function gate(verdict, name, summary, detail) {
  return { verdict, name, summary, detail };
}

function overallVerdict(gates) {
  if (gates.some((entry) => entry.verdict === "no-go")) {
    return "no-go";
  }

  if (gates.some((entry) => entry.verdict === "partial")) {
    return "partial";
  }

  return "go";
}

function printSummary(report, reportPath) {
  console.log("");
  console.log(`Release check: ${report.overallVerdict.toUpperCase()}`);
  for (const entry of report.gates) {
    console.log(`- ${entry.name}: ${entry.verdict.toUpperCase()} - ${entry.summary}`);
  }
  console.log(`- Report: ${reportPath}`);
}

const commands = [];

if (!skipBuild) {
  commands.push(runCommand("npm", ["run", "typecheck"]));
  commands.push(runCommand("npm", ["run", "package:plugin"]));
}

let helperStatus = null;
let debugSnapshot = null;
let helperError = null;

if (existsSync(helperPath)) {
  try {
    helperStatus = readJsonCommand(helperPath, ["status"]);
    debugSnapshot = readJsonCommand(helperPath, ["debug"]);
  } catch (error) {
    helperError = String(error);
  }
} else {
  helperError = `Bundled helper is missing at ${helperPath}.`;
}

const installedPlugin = detectInstalledPlugin();
const bundleEvidence = buildBundleEvidence();
const pluginLogTail = tailLines(pluginLogPath, 20);
const streamDeckLogTail = tailLines(streamDeckLogPath, 120);
const buildCommandsPassed =
  skipBuild || commands.every((commandResult) => commandResult.ok);
const bundleComplete = bundleEvidence.every((entry) => entry.exists);
const packagedArtifactExists = existsSync(packagedArtifactPath);
const statusPayload = helperStatus?.payload ?? null;
const debugPayload = debugSnapshot?.payload ?? null;
const accessibilityTrusted =
  statusPayload?.permissions?.accessibilityTrusted === true;
const debugCapturedWindows = debugPayload?.windows?.length ?? 0;
const screenRecorderShortcutDisabled =
  typeof statusPayload?.detail === "string" &&
  statusPayload.detail.includes("Screen Recorder shortcut appears disabled");
const recordShortcutBlocksPublicAction =
  recordActionPublished && screenRecorderShortcutDisabled;

const gates = [
  gate(
    buildCommandsPassed && bundleComplete && packagedArtifactExists ? "go" : "no-go",
    "Build And Package",
    buildCommandsPassed && bundleComplete && packagedArtifactExists
      ? "Typecheck, packaging, bundle contents, and artifact checks passed."
      : "Build/package proof is incomplete.",
    buildCommandsPassed
      ? "The packaged plugin bundle contains the required runtime, helper, UI, and asset files."
      : "Review the recorded command output in the JSON report to see which build step failed."
  ),
  gate(
    installedPlugin.exists && connectedInStreamDeckLog() ? "go" : "partial",
    "Install And Discoverability",
    installedPlugin.exists && connectedInStreamDeckLog()
      ? "The plugin is installed locally and Stream Deck logged a successful plugin connection."
      : "The repo bundle exists, but local install proof is incomplete.",
    installedPlugin.exists
      ? "The installed plugin path exists, but Stream Deck connection evidence may need a fresh app launch."
      : "Install the bundled plugin into Stream Deck before calling this lane green."
  ),
  gate(
    helperError
      ? "no-go"
      : accessibilityTrusted
        ? "go"
        : "partial",
    "Permission Handling",
    helperError
      ? "The helper could not produce a status report."
      : accessibilityTrusted
        ? "Accessibility is granted, so pause/resume and stop can be validated."
        : "Accessibility is still missing, so pause/resume and stop are blocked.",
    helperError
      ? helperError
      : accessibilityTrusted
        ? "The helper can inspect Descript's UI surface on this machine."
        : "This is the current blocker for the real on-field test."
  ),
  gate(
    helperError
      ? "no-go"
      : !statusPayload?.descript?.isRunning
        ? "no-go"
        : recordShortcutBlocksPublicAction
          ? "no-go"
        : !accessibilityTrusted
          ? "no-go"
          : debugCapturedWindows > 0
            ? "partial"
            : "no-go",
    "Screen Recorder Release Gate",
    helperError
      ? "No helper evidence is available."
      : !statusPayload?.descript?.isRunning
        ? "Descript is not running, so the recorder gate cannot be tested."
        : recordShortcutBlocksPublicAction
          ? "Descript's local Screen Recorder shortcut is disabled, so the published Record action is blocked."
        : !accessibilityTrusted
          ? "Accessibility is missing, so the recorder gate is blocked."
        : debugCapturedWindows > 0
            ? screenRecorderShortcutDisabled
              ? "Pause / Resume and Stop are ready for the live drill; the hidden Record shortcut lane is still blocked."
              : "Accessibility can see Descript, but the 10-attempt live cycle still needs to be completed."
            : "Accessibility is granted, but no Descript UI snapshot was captured.",
    helperError
      ? helperError
      : !accessibilityTrusted
        ? "Grant Accessibility to the helper, then rerun the release check and the live 10-attempt cycle."
        : recordShortcutBlocksPublicAction
          ? "Restore or reassign Descript's Screen Recorder shortcut before trusting the published Record action."
        : debugCapturedWindows > 0
          ? screenRecorderShortcutDisabled
            ? "Record is not part of the current packaged beta action set, so this warning is tracked as experimental. Complete the live Pause / Resume and Stop drill before sharing broadly."
            : "This lane is ready for the manual reliability drill: start, pause, resume, stop repeated 10 times."
          : "Open the target recorder in Descript and capture a real debug snapshot before trusting selectors."
  )
];

const report = {
  createdAt: new Date().toISOString(),
  stage: "screen-recorder-beta",
  overallVerdict: overallVerdict(gates),
  environment: {
    platform: process.platform,
    nodeVersion: process.version,
    descriptVersion: statusPayload?.descript?.version ?? null
  },
  gates,
  evidence: {
    commands,
    bundleEvidence,
    publishedActionIds,
    recordActionPublished,
    screenRecorderShortcutDisabled,
    packagedArtifactPath,
    packagedArtifactExists,
    helperStatus,
    debugSnapshot,
    helperError,
    installedPlugin: {
      path: installedPluginPath,
      ...installedPlugin
    },
    pluginLogPath,
    pluginLogTail,
    streamDeckLogPath,
    streamDeckLogTail
  }
};

mkdirSync(artifactDir, { recursive: true });
const timestamp = report.createdAt.replaceAll(":", "-");
const reportPath = join(artifactDir, `${timestamp}.json`);
writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");

printSummary(report, reportPath);

if (report.overallVerdict === "no-go") {
  process.exitCode = 1;
}
