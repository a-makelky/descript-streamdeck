import { randomUUID } from "node:crypto";
import {
  spawn,
  type ChildProcessWithoutNullStreams
} from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import streamDeck from "@elgato/streamdeck";
import type {
  ActionSettings,
  BridgeCommandType,
  BridgeRequest,
  BridgeResponse,
  CommandResultPayload,
  CommandOptions,
  DebugSnapshotPayload,
  HelperStatus
} from "@descript-streamdeck/shared";
import { isBridgeResponse, mergeSettings } from "@descript-streamdeck/shared";

type PendingRequest = {
  reject: (error: Error) => void;
  resolve: (response: BridgeResponse) => void;
  timeout: NodeJS.Timeout;
};

export class HelperProcess {
  private buffer = "";
  private child: ChildProcessWithoutNullStreams | undefined;
  private readonly pending = new Map<string, PendingRequest>();
  private requestQueue: Promise<void> = Promise.resolve();

  async getStatus(settings?: Partial<ActionSettings>): Promise<HelperStatus> {
    const response = await this.request("getStatus", mergeSettings(settings));
    if (response.type !== "status") {
      throw new Error(`Expected status response, received ${response.type}.`);
    }

    return response.payload;
  }

  async runCommand(
    type: Extract<BridgeCommandType, "record" | "pauseResume" | "stop">,
    settings?: Partial<ActionSettings>
  ): Promise<CommandResultPayload> {
    const response = await this.request(type, mergeSettings(settings));
    if (response.type !== "commandResult") {
      throw new Error(`Expected commandResult response, received ${response.type}.`);
    }

    return response.payload;
  }

  async openPermissions(): Promise<CommandResultPayload> {
    const response = await this.request("openPermissions");
    if (response.type !== "commandResult") {
      throw new Error(`Expected commandResult response, received ${response.type}.`);
    }

    return response.payload;
  }

  async debugSnapshot(): Promise<DebugSnapshotPayload> {
    const response = await this.request("debugSnapshot");
    if (response.type !== "debugSnapshot") {
      throw new Error(`Expected debugSnapshot response, received ${response.type}.`);
    }

    return response.payload;
  }

  private async request(
    type: BridgeCommandType,
    payload?: CommandOptions
  ): Promise<BridgeResponse> {
    const queuedRequest = this.requestQueue.then(
      () => this.sendRequest(type, payload),
      () => this.sendRequest(type, payload)
    );
    this.requestQueue = queuedRequest.then(
      () => undefined,
      () => undefined
    );
    return queuedRequest;
  }

  private async sendRequest(
    type: BridgeCommandType,
    payload?: CommandOptions
  ): Promise<BridgeResponse> {
    const child = this.ensureChild();
    const id = randomUUID();
    const timeoutMs = this.timeoutFor(type);

    return new Promise<BridgeResponse>((resolvePromise, rejectPromise) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        rejectPromise(
          new Error(`Helper timed out while handling ${type} after ${timeoutMs}ms.`)
        );
      }, timeoutMs);

      this.pending.set(id, {
        reject: rejectPromise,
        resolve: resolvePromise,
        timeout
      });

      const request: BridgeRequest = {
        id,
        type,
        payload
      };

      child.stdin.write(`${JSON.stringify(request)}\n`);
    });
  }

  private timeoutFor(type: BridgeCommandType): number {
    switch (type) {
      case "record":
        return 18_000;
      case "stop":
      case "pauseResume":
        return 10_000;
      case "getStatus":
      case "debugSnapshot":
        return 12_000;
      case "openPermissions":
        return 8_000;
      default:
        return 5_000;
    }
  }

  private ensureChild(): ChildProcessWithoutNullStreams {
    if (this.child && !this.child.killed) {
      return this.child;
    }

    const helperPath = resolve(__dirname, "../../bin/descript-bridge");
    if (!existsSync(helperPath)) {
      throw new Error(
        `Bundled helper not found at ${helperPath}. Run npm run build first.`
      );
    }

    const child = spawn(helperPath, [], {
      stdio: ["pipe", "pipe", "pipe"]
    });

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      this.buffer += chunk;
      this.flushBuffer();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      for (const line of chunk.split("\n")) {
        if (line.trim()) {
          streamDeck.logger.warn(`[helper] ${line}`);
        }
      }
    });

    child.on("exit", (code: number | null, signal: NodeJS.Signals | null) => {
      const message = `Helper exited with code ${code ?? "unknown"} and signal ${signal ?? "none"}.`;
      streamDeck.logger.warn(message);
      this.child = undefined;
      this.buffer = "";

      for (const [id, pending] of this.pending) {
        clearTimeout(pending.timeout);
        pending.reject(new Error(message));
        this.pending.delete(id);
      }
    });

    child.on("error", (error: Error) => {
      streamDeck.logger.error(`Failed to launch helper: ${String(error)}`);
    });

    this.child = child;
    return child;
  }

  private flushBuffer(): void {
    let newlineIndex = this.buffer.indexOf("\n");
    while (newlineIndex >= 0) {
      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);

      if (line) {
        this.handleLine(line);
      }

      newlineIndex = this.buffer.indexOf("\n");
    }
  }

  private handleLine(line: string): void {
    try {
      const decoded = JSON.parse(line) as unknown;
      if (!isBridgeResponse(decoded)) {
        streamDeck.logger.warn(`Discarded malformed helper payload: ${line}`);
        return;
      }

      const pending = this.pending.get(decoded.id);
      if (!pending) {
        streamDeck.logger.warn(`Received orphaned helper response for ${decoded.id}.`);
        return;
      }

      clearTimeout(pending.timeout);
      this.pending.delete(decoded.id);

      if (decoded.type === "error") {
        pending.reject(new Error(decoded.payload.message));
        return;
      }

      pending.resolve(decoded);
    } catch (error) {
      streamDeck.logger.error(`Failed to decode helper output: ${String(error)}`);
    }
  }
}

export const helperProcess = new HelperProcess();
