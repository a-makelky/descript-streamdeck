import type { HelperStatus, RecorderState } from "@descript-streamdeck/shared";

export type KeyPresentation = {
  state?: 0 | 1;
  title: string;
};

function compactTitle(primary: string, secondary?: string): string {
  return secondary ? `${primary}\n${secondary}` : primary;
}

function isControllableState(state: RecorderState): boolean {
  return state === "recording" || state === "paused";
}

export function presentRecordStop(status: HelperStatus): KeyPresentation {
  if (!status.descript.isRunning) {
    return { title: compactTitle("Open", "Descript"), state: 0 };
  }

  if (!status.permissions.accessibilityTrusted && !status.supportedActions.record) {
    return { title: compactTitle("Allow", "Access"), state: 0 };
  }

  switch (status.recorderState) {
    case "recording":
      return { title: "Stop", state: 1 };
    case "paused":
      return { title: "Stop", state: 1 };
    default:
      return { title: "Record", state: 0 };
  }
}

export const presentRecord = presentRecordStop;

export function presentPauseResume(status: HelperStatus): KeyPresentation {
  if (!status.descript.isRunning) {
    return { title: compactTitle("No", "App"), state: 0 };
  }

  if (!status.permissions.accessibilityTrusted) {
    return { title: compactTitle("Allow", "Access"), state: 0 };
  }

  if (status.recorderState === "paused") {
    return { title: "Resume", state: 1 };
  }

  if (status.recorderState === "recording") {
    return { title: "Pause", state: 0 };
  }

  return {
    title: isControllableState(status.recorderState)
      ? "Pause"
      : compactTitle("No", "Session"),
    state: 0
  };
}

export function presentStop(status: HelperStatus): KeyPresentation {
  return presentRecordStop(status);
}
