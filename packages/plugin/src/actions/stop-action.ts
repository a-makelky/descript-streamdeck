import { action } from "@elgato/streamdeck";
import type { HelperStatus } from "@descript-streamdeck/shared";
import { presentStop } from "../state/presentation.js";
import { RecorderAction } from "./recorder-action.js";

@action({ UUID: "com.descript.streamdeck.stop" })
export class StopAction extends RecorderAction {
  protected readonly commandName = "stop" as const;

  protected present(status: HelperStatus) {
    return presentStop(status);
  }
}

