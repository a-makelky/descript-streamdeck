import { action } from "@elgato/streamdeck";
import type { HelperStatus } from "@descript-streamdeck/shared";
import { presentRecordStop } from "../state/presentation.js";
import { RecorderAction } from "./recorder-action.js";

@action({ UUID: "com.descript.streamdeck.stop" })
export class StopAction extends RecorderAction {
  protected readonly commandName = "stop" as const;

  protected commandForStatus(status: HelperStatus) {
    return status.recorderState === "recording" || status.recorderState === "paused"
      ? "stop"
      : "record";
  }

  protected present(status: HelperStatus) {
    return presentRecordStop(status);
  }
}
