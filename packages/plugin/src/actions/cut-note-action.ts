import { action } from "@elgato/streamdeck";
import type { HelperStatus } from "@descript-streamdeck/shared";
import { presentCutNote } from "../state/presentation.js";
import { RecorderAction } from "./recorder-action.js";

@action({ UUID: "com.descript.streamdeck.cutNote" })
export class CutNoteAction extends RecorderAction {
  protected readonly commandName = "cutNote" as const;

  protected present(status: HelperStatus) {
    return presentCutNote(status);
  }
}
