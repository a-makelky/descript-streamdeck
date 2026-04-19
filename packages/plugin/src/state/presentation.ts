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

export function presentRecord(status: HelperStatus): KeyPresentation {
  if (!status.descript.isRunning) {
    return { title: compactTitle("Open", "Descript") };
  }

  if (!status.permissions.accessibilityTrusted && !status.supportedActions.record) {
    return { title: compactTitle("Allow", "Access") };
  }

  switch (status.recorderState) {
    case "recording":
      return { title: compactTitle("Live", "Recording") };
    case "paused":
      return { title: compactTitle("Ready", "Resume") };
    default:
      return { title: "Record" };
  }
}

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
  if (!status.descript.isRunning) {
    return { title: compactTitle("No", "App") };
  }

  if (!status.permissions.accessibilityTrusted) {
    return { title: compactTitle("Allow", "Access") };
  }

  if (status.recorderState === "recording" || status.recorderState === "paused") {
    return { title: "Stop" };
  }

  return { title: compactTitle("No", "Session") };
}

