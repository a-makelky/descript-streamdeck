import { action } from "@elgato/streamdeck";
import type { HelperStatus } from "@descript-streamdeck/shared";
import { presentRecordStop } from "../state/presentation.js";
import { RecorderAction } from "./recorder-action.js";

@action({ UUID: "com.descript.streamdeck.record" })
export class RecordAction extends RecorderAction {
  protected readonly commandName = "record" as const;

  protected override commandForStatus(status: HelperStatus) {
    return status.recorderState === "recording" || status.recorderState === "paused"
      ? "stop"
      : "record";
  }

  protected present(status: HelperStatus) {
    return presentRecordStop(status);
  }
}
