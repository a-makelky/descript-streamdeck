import {
  SingletonAction,
  type DidReceiveSettingsEvent,
  type KeyAction,
  type KeyDownEvent,
  type WillAppearEvent,
  type WillDisappearEvent
} from "@elgato/streamdeck";
import { appendFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import streamDeck from "@elgato/streamdeck";
import type { ActionSettings, HelperStatus } from "@descript-streamdeck/shared";
import { mergeSettings } from "@descript-streamdeck/shared";
import { helperProcess } from "../bridge/helper-process.js";
import type { KeyPresentation } from "../state/presentation.js";

type CommandName = "record" | "pauseResume" | "stop";

type VisibleContext = {
  action: KeyAction<ActionSettings>;
  settings: ActionSettings;
};

const runtimeLogPath = resolve(__dirname, "../../logs/runtime-events.jsonl");

function writeRuntimeEvent(event: Record<string, unknown>): void {
  try {
    mkdirSync(resolve(__dirname, "../../logs"), { recursive: true });
    appendFileSync(
      runtimeLogPath,
      `${JSON.stringify({ at: new Date().toISOString(), ...event })}\n`,
      "utf8"
    );
  } catch {
    // Runtime diagnostics must never break the action flow.
  }
}

export abstract class RecorderAction extends SingletonAction<ActionSettings> {
  private readonly contexts = new Map<string, VisibleContext>();
  private readonly lastPresentations = new Map<string, KeyPresentation>();
  private readonly lastStatuses = new Map<string, HelperStatus>();
  private refreshTimer: NodeJS.Timeout | undefined;
  private refreshInFlight = false;

  protected abstract readonly commandName: CommandName;
  protected abstract present(status: HelperStatus): KeyPresentation;

  protected commandForStatus(_status: HelperStatus): CommandName {
    return this.commandName;
  }

  protected commandForStatusError(_error: unknown): CommandName {
    return this.commandName;
  }

  override async onDidReceiveSettings(
    ev: DidReceiveSettingsEvent<ActionSettings>
  ): Promise<void> {
    if (!ev.action.isKey()) {
      return;
    }

    const settings = mergeSettings(ev.payload.settings);
    this.contexts.set(ev.action.id, {
      action: ev.action,
      settings
    });
    await this.render(ev.action, settings);
  }

  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    const settings = mergeSettings(ev.payload.settings);

    try {
      const statusResult = await this.statusForAction(ev.action.id, settings);
      const command = statusResult.status
        ? this.commandForStatus(statusResult.status)
        : this.commandForStatusError(statusResult.error);
      const result = await helperProcess.runCommand(command, settings);
      let debugSnapshot: unknown;
      if (!result.ok || command !== "record") {
        try {
          debugSnapshot = await helperProcess.debugSnapshot();
        } catch (debugError) {
          debugSnapshot = {
            error: String(debugError)
          };
        }
      }

      writeRuntimeEvent({
        actionId: ev.action.id,
        command,
        settings,
        beforeStatus: statusResult.status ?? null,
        statusError: statusResult.error ? String(statusResult.error) : undefined,
        result,
        debugSnapshot
      });

      const detail = result.message ? ` ${result.message}` : "";
      const presentation = this.present(result.status);
      this.lastStatuses.set(ev.action.id, result.status);
      this.lastPresentations.set(ev.action.id, presentation);
      ev.action.setTitle(presentation.title).catch(() => {});
      if (presentation.state !== undefined) {
        ev.action.setState(presentation.state).catch(() => {});
      }
      streamDeck.logger.info(
        `[descript-streamdeck] ${command} -> ${result.ok ? "ok" : "failed"}:${detail}`
      );
      if (result.ok) {
        await ev.action.showOk();
      } else {
        await ev.action.showAlert();
      }
    } catch (error) {
      writeRuntimeEvent({
        actionId: ev.action.id,
        command: this.commandName,
        settings,
        error: String(error)
      });
      streamDeck.logger.error(
        `[descript-streamdeck] ${this.commandName} -> exception: ${String(error)}`
      );
      await ev.action.showAlert();
    }

    await this.refreshAll();
  }

  override async onWillAppear(
    ev: WillAppearEvent<ActionSettings>
  ): Promise<void> {
    if (!ev.action.isKey()) {
      return;
    }

    const settings = mergeSettings(ev.payload.settings);
    this.contexts.set(ev.action.id, {
      action: ev.action,
      settings
    });
    this.startRefreshing();
    await this.render(ev.action, settings);
  }

  override async onWillDisappear(
    ev: WillDisappearEvent<ActionSettings>
  ): Promise<void> {
    this.contexts.delete(ev.action.id);
    this.lastPresentations.delete(ev.action.id);
    this.lastStatuses.delete(ev.action.id);
    if (this.contexts.size === 0) {
      this.stopRefreshing();
    }
  }

  async refreshVisibleActions(): Promise<void> {
    await this.refreshAll();
  }

  protected async render(
    action: KeyAction<ActionSettings>,
    settings: ActionSettings
  ): Promise<void> {
    try {
      const status = await helperProcess.getStatus(settings);
      const presentation = this.present(status);
      this.lastStatuses.set(action.id, status);
      this.lastPresentations.set(action.id, presentation);
      await action.setTitle(presentation.title);
      if (presentation.state !== undefined) {
        await action.setState(presentation.state);
      }
    } catch (error) {
      streamDeck.logger.warn(
        `[descript-streamdeck] render ${this.commandName} -> skipped status refresh: ${String(error)}`
      );
      const fallback = this.lastPresentations.get(action.id) ?? {
        title: "Record",
        state: 0
      };
      await action.setTitle(fallback.title);
      if (fallback.state !== undefined) {
        await action.setState(fallback.state);
      }
    }
  }

  private async statusForAction(
    actionId: string,
    settings: ActionSettings
  ): Promise<{ error?: unknown; status?: HelperStatus }> {
    try {
      const status = await helperProcess.getStatus(settings);
      this.lastStatuses.set(actionId, status);
      return { status };
    } catch (error) {
      const cachedStatus = this.lastStatuses.get(actionId);
      if (cachedStatus) {
        streamDeck.logger.warn(
          `[descript-streamdeck] using cached status after getStatus failed: ${String(error)}`
        );
        return { error, status: cachedStatus };
      }

      streamDeck.logger.warn(
        `[descript-streamdeck] using fallback command after getStatus failed: ${String(error)}`
      );
      return { error };
    }
  }

  private startRefreshing(): void {
    if (this.refreshTimer) {
      return;
    }

    this.refreshTimer = setInterval(() => {
      void this.refreshAll();
    }, 2_500);
  }

  private stopRefreshing(): void {
    if (!this.refreshTimer) {
      return;
    }

    clearInterval(this.refreshTimer);
    this.refreshTimer = undefined;
  }

  private async refreshAll(): Promise<void> {
    if (this.refreshInFlight) {
      return;
    }

    this.refreshInFlight = true;
    try {
      const tasks = Array.from(this.contexts.values()).map(({ action, settings }) =>
        this.render(action, settings)
      );
      await Promise.allSettled(tasks);
    } finally {
      this.refreshInFlight = false;
    }
  }
}
