import { action } from "@elgato/streamdeck";
import type { HelperStatus } from "@descript-streamdeck/shared";
import { presentPauseResume } from "../state/presentation.js";
import { RecorderAction } from "./recorder-action.js";

@action({ UUID: "com.descript.streamdeck.pauseResume" })
export class PauseResumeAction extends RecorderAction {
  protected readonly commandName = "pauseResume" as const;

  protected override fallbackPresentation() {
    return {
      title: "Pause",
      state: 0 as const
    };
  }

  protected present(status: HelperStatus) {
    return presentPauseResume(status);
  }
}
