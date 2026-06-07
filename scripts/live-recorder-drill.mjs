import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const helperPath = join(
  rootDir,
  "packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge"
);
const artifactDir = join(rootDir, "artifacts/live-recorder-drill");
const attempts = readNumberFlag("--attempts", 10);
const setupTimeoutMs = readNumberFlag("--setup-timeout-ms", 12_000);
const stopTimeoutMs = readNumberFlag("--stop-timeout-ms", 5_000);

function readNumberFlag(name, fallback) {
  const entry = process.argv.find((arg) => arg.startsWith(`${name}=`));
  if (!entry) {
    return fallback;
  }

  const value = Number(entry.slice(name.length + 1));
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function sleep(ms) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

function runHelper(command) {
  const result = spawnSync(helperPath, [command], {
    cwd: rootDir,
    encoding: "utf8"
  });

  if (result.status !== 0) {
    throw new Error(
      `${command} failed: ${result.stderr || result.stdout || "no output"}`
    );
  }

  return JSON.parse(result.stdout);
}

function statusSnapshot() {
  return runHelper("status").payload;
}

function isActive(status) {
  return status.recorderState === "recording" || status.recorderState === "paused";
}

async function waitForState(states, timeoutMs, pollMs = 250) {
  const targetStates = new Set(states);
  const deadline = Date.now() + timeoutMs;
  let latest = statusSnapshot();

  while (Date.now() < deadline) {
    latest = statusSnapshot();
    if (targetStates.has(latest.recorderState)) {
      return latest;
    }

    await sleep(pollMs);
  }

  return latest;
}

async function ensureIdle() {
  const before = statusSnapshot();
  if (!isActive(before)) {
    return {
      before,
      command: null,
      after: before
    };
  }

  const command = runHelper("stop").payload;
  const after = await waitForState(["idle"], stopTimeoutMs);
  return {
    before,
    command,
    after
  };
}

async function runRecordStopAttempt(index) {
  const idleSetup = await ensureIdle();
  const beforeRecord = statusSnapshot();
  const record = runHelper("record").payload;
  let afterRecord = record.status;

  if (!isActive(afterRecord)) {
    afterRecord = await waitForState(["recording", "paused"], setupTimeoutMs);
  }

  const beforeStop = statusSnapshot();
  const stop = runHelper("stop").payload;
  let afterStop = stop.status;

  if (afterStop.recorderState !== "idle") {
    afterStop = await waitForState(["idle"], stopTimeoutMs);
  }

  const recordPassed =
    record.ok === true &&
    !isActive(beforeRecord) &&
    isActive(afterRecord);
  const stopPassed =
    stop.ok === true &&
    isActive(beforeStop) &&
    afterStop.recorderState === "idle";

  return {
    index,
    idleSetup,
    record: {
      beforeState: beforeRecord.recorderState,
      commandOk: record.ok,
      message: record.message ?? null,
      afterState: afterRecord.recorderState,
      passed: recordPassed
    },
    stop: {
      beforeState: beforeStop.recorderState,
      commandOk: stop.ok,
      message: stop.message ?? null,
      afterState: afterStop.recorderState,
      passed: stopPassed
    },
    passed: recordPassed && stopPassed
  };
}

async function cleanupActiveRecording() {
  const current = statusSnapshot();
  if (!isActive(current)) {
    return null;
  }

  const result = runHelper("stop").payload;
  const after = await waitForState(["idle"], stopTimeoutMs);
  return {
    beforeState: current.recorderState,
    commandOk: result.ok,
    message: result.message ?? null,
    afterState: after.recorderState
  };
}

async function main() {
  mkdirSync(artifactDir, { recursive: true });

  const startedAt = new Date().toISOString();
  const report = {
    startedAt,
    completedAt: null,
    error: null,
    environment: {
      helperPath,
      attempts,
      setupTimeoutMs,
      stopTimeoutMs
    },
    initialStatus: statusSnapshot(),
    attempts: [],
    cleanup: null,
    summary: null
  };

  try {
    for (let index = 1; index <= attempts; index += 1) {
      report.attempts.push(await runRecordStopAttempt(index));
      await sleep(500);
    }
  } catch (error) {
    report.error = String(error);
  } finally {
    report.cleanup = await cleanupActiveRecording();
  }

  const passedCount = report.attempts.filter((attempt) => attempt.passed).length;
  report.completedAt = new Date().toISOString();
  report.finalStatus = statusSnapshot();
  report.summary = {
    verdict: !report.error && passedCount === attempts ? "go" : "no-go",
    passedCount,
    attempts
  };

  const timestamp = report.startedAt.replaceAll(":", "-");
  const reportPath = join(artifactDir, `${timestamp}.json`);
  writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");

  console.log("");
  console.log(`Live recorder drill: ${report.summary.verdict.toUpperCase()}`);
  console.log(`- Record + Stop: ${passedCount}/${attempts}`);
  if (report.error) {
    console.log(`- Error: ${report.error}`);
  }
  console.log(`- Report: ${reportPath}`);

  if (report.summary.verdict !== "go") {
    process.exitCode = 1;
  }
}

await main();
