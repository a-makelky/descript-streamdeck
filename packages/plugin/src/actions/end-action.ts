import { action } from "@elgato/streamdeck";
import type { HelperStatus } from "@descript-streamdeck/shared";
import { presentEnd } from "../state/presentation.js";
import { RecorderAction } from "./recorder-action.js";

@action({ UUID: "com.descript.streamdeck.end" })
export class EndAction extends RecorderAction {
  protected readonly commandName = "stop" as const;

  protected override commandForStatus(status: HelperStatus) {
    void status;
    return "stop" as const;
  }

  protected override commandForStatusError() {
    return "stop" as const;
  }

  protected present(status: HelperStatus) {
    return presentEnd(status);
  }
}
