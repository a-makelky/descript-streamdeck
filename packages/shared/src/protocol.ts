export const protocolVersion = "0.1.0";

export type RecorderKind = "auto" | "screen" | "editor";
export type RecorderState =
  | "idle"
  | "recording"
  | "paused"
  | "unavailable"
  | "unknown";

export type BridgeCommandType =
  | "ping"
  | "getStatus"
  | "record"
  | "pauseResume"
  | "stop"
  | "cutNote"
  | "openPermissions"
  | "debugSnapshot";

export type ActionSettings = {
  [key: string]: boolean | string | undefined;
  preferredRecorder: RecorderKind;
  bringDescriptToFront: boolean;
  allowHotkeyFallback: boolean;
  openPermissionsIfNeeded: boolean;
  screenRecorderShortcut: string;
  cutNoteText: string;
};

export const defaultActionSettings: ActionSettings = {
  preferredRecorder: "auto",
  bringDescriptToFront: true,
  allowHotkeyFallback: true,
  openPermissionsIfNeeded: true,
  screenRecorderShortcut: "cmd+shift+2",
  cutNoteText: "CUT"
};

export type CommandOptions = ActionSettings;

export interface DescriptAppInfo {
  bundleId: string;
  isRunning: boolean;
  version?: string;
}

export interface PermissionStatus {
  accessibilityTrusted: boolean;
}

export interface SupportedActions {
  record: boolean;
  pauseResume: boolean;
  stop: boolean;
}

export interface HelperStatus {
  descript: DescriptAppInfo;
  permissions: PermissionStatus;
  preferredRecorder: RecorderKind;
  activeRecorder: Exclude<RecorderKind, "auto"> | null;
  recorderState: RecorderState;
  supportedActions: SupportedActions;
  detail?: string;
}

export interface BridgeRequest {
  id: string;
  type: BridgeCommandType;
  payload?: CommandOptions | undefined;
}

export interface CommandResultPayload {
  ok: boolean;
  message?: string;
  status: HelperStatus;
}

export interface DebugSnapshotPayload {
  summary: string;
  windows: Array<{
    title: string;
    role: string;
    buttons: string[];
    elements: Array<{
      role: string;
      label: string;
      depth: number;
    }>;
  }>;
}

interface ResponseBase<TType extends string, TPayload> {
  id: string;
  type: TType;
  payload: TPayload;
}

export type BridgeResponse =
  | ResponseBase<
      "pong",
      {
        helperVersion: string;
        protocolVersion: string;
      }
    >
  | ResponseBase<"status", HelperStatus>
  | ResponseBase<"commandResult", CommandResultPayload>
  | ResponseBase<"debugSnapshot", DebugSnapshotPayload>
  | ResponseBase<
      "error",
      {
        code: string;
        message: string;
        recoverable: boolean;
      }
    >;

export function mergeSettings(
  settings: Partial<ActionSettings> | undefined
): ActionSettings {
  return {
    ...defaultActionSettings,
    ...settings
  };
}

export function isBridgeResponse(value: unknown): value is BridgeResponse {
  if (!value || typeof value !== "object") {
    return false;
  }

  const candidate = value as Partial<BridgeResponse>;
  return typeof candidate.id === "string" && typeof candidate.type === "string";
}
