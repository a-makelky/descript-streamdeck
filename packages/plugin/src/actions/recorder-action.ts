import {
  SingletonAction,
  type DidReceiveSettingsEvent,
  type KeyAction,
  type KeyDownEvent,
  type WillAppearEvent,
  type WillDisappearEvent
} from "@elgato/streamdeck";
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

export abstract class RecorderAction extends SingletonAction<ActionSettings> {
  private readonly contexts = new Map<string, VisibleContext>();
  private refreshTimer: NodeJS.Timeout | undefined;
  private refreshInFlight = false;

  protected abstract readonly commandName: CommandName;
  protected abstract present(status: HelperStatus): KeyPresentation;

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
      const result = await helperProcess.runCommand(this.commandName, settings);
      const detail = result.message ? ` ${result.message}` : "";
      ev.action.setTitle(this.present(result.status).title).catch(() => {});
      streamDeck.logger.info(
        `[descript-streamdeck] ${this.commandName} -> ${result.ok ? "ok" : "failed"}:${detail}`
      );
      if (result.ok) {
        await ev.action.showOk();
      } else {
        await ev.action.showAlert();
      }
    } catch (error) {
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
      await action.setTitle(presentation.title);
      if (presentation.state !== undefined) {
        await action.setState(presentation.state);
      }
    } catch (error) {
      streamDeck.logger.error(
        `[descript-streamdeck] render ${this.commandName} -> exception: ${String(error)}`
      );
      await action.setTitle("Unavailable");
      await action.showAlert();
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
