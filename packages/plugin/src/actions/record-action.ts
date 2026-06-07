import { action } from "@elgato/streamdeck";
import type { HelperStatus } from "@descript-streamdeck/shared";
import { presentStart } from "../state/presentation.js";
import { RecorderAction } from "./recorder-action.js";

@action({ UUID: "com.descript.streamdeck.record" })
export class RecordAction extends RecorderAction {
  protected readonly commandName = "record" as const;

  protected override commandForStatus(status: HelperStatus) {
    void status;
    return "record" as const;
  }

  protected present(status: HelperStatus) {
    return presentStart(status);
  }
}
