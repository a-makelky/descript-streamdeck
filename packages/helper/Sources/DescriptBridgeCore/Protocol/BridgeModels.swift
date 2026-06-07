import Foundation

public let helperVersion = "0.1.0"
public let helperProtocolVersion = "0.1.0"

public enum RecorderKind: String, Codable {
    case auto
    case screen
    case editor
}

public enum RecorderState: String, Codable {
    case idle
    case recording
    case paused
    case unavailable
    case unknown
}

public struct CommandOptions: Codable {
    public let preferredRecorder: RecorderKind
    public let bringDescriptToFront: Bool
    public let allowHotkeyFallback: Bool
    public let openPermissionsIfNeeded: Bool
    public let screenRecorderShortcut: String
    public let cutNoteText: String

    public init(
        preferredRecorder: RecorderKind = .auto,
        bringDescriptToFront: Bool = true,
        allowHotkeyFallback: Bool = true,
        openPermissionsIfNeeded: Bool = true,
        screenRecorderShortcut: String = "cmd+shift+2",
        cutNoteText: String = "CUT"
    ) {
        self.preferredRecorder = preferredRecorder
        self.bringDescriptToFront = bringDescriptToFront
        self.allowHotkeyFallback = allowHotkeyFallback
        self.openPermissionsIfNeeded = openPermissionsIfNeeded
        self.screenRecorderShortcut = screenRecorderShortcut
        self.cutNoteText = cutNoteText
    }

    private enum CodingKeys: String, CodingKey {
        case preferredRecorder
        case bringDescriptToFront
        case allowHotkeyFallback
        case openPermissionsIfNeeded
        case screenRecorderShortcut
        case cutNoteText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredRecorder = try container.decodeIfPresent(
            RecorderKind.self,
            forKey: .preferredRecorder
        ) ?? .auto
        bringDescriptToFront = try container.decodeIfPresent(
            Bool.self,
            forKey: .bringDescriptToFront
        ) ?? true
        allowHotkeyFallback = try container.decodeIfPresent(
            Bool.self,
            forKey: .allowHotkeyFallback
        ) ?? true
        openPermissionsIfNeeded = try container.decodeIfPresent(
            Bool.self,
            forKey: .openPermissionsIfNeeded
        ) ?? true
        screenRecorderShortcut = try container.decodeIfPresent(
            String.self,
            forKey: .screenRecorderShortcut
        ) ?? "cmd+shift+2"
        cutNoteText = try container.decodeIfPresent(
            String.self,
            forKey: .cutNoteText
        ) ?? "CUT"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferredRecorder, forKey: .preferredRecorder)
        try container.encode(bringDescriptToFront, forKey: .bringDescriptToFront)
        try container.encode(allowHotkeyFallback, forKey: .allowHotkeyFallback)
        try container.encode(openPermissionsIfNeeded, forKey: .openPermissionsIfNeeded)
        try container.encode(screenRecorderShortcut, forKey: .screenRecorderShortcut)
        try container.encode(cutNoteText, forKey: .cutNoteText)
    }
}

public struct DescriptAppInfo: Codable {
    public let bundleId: String
    public let isRunning: Bool
    public let version: String?
}

public struct PermissionStatus: Codable {
    public let accessibilityTrusted: Bool
}

public struct SupportedActions: Codable {
    public let record: Bool
    public let pauseResume: Bool
    public let stop: Bool
}

public struct HelperStatus: Codable {
    public let descript: DescriptAppInfo
    public let permissions: PermissionStatus
    public let preferredRecorder: RecorderKind
    public let activeRecorder: RecorderKind?
    public let recorderState: RecorderState
    public let supportedActions: SupportedActions
    public let detail: String?
}

public enum BridgeCommandType: String, Codable {
    case ping
    case getStatus
    case record
    case pauseResume
    case stop
    case cutNote
    case openPermissions
    case debugSnapshot
}

public struct BridgeRequest: Codable {
    public let id: String
    public let type: BridgeCommandType
    public let payload: CommandOptions?
}

public struct PongPayload: Codable {
    public let helperVersion: String
    public let protocolVersion: String
}

public struct CommandResultPayload: Codable {
    public let ok: Bool
    public let message: String?
    public let status: HelperStatus
}

public struct WindowDebugSnapshot: Codable {
    public let title: String
    public let role: String
    public let buttons: [String]
    public let elements: [DebugElementSnapshot]
}

public struct DebugElementSnapshot: Codable {
    public let role: String
    public let label: String
    public let depth: Int
}

public struct DebugSnapshotPayload: Codable {
    public let summary: String
    public let windows: [WindowDebugSnapshot]
}

public struct ErrorPayload: Codable {
    public let code: String
    public let message: String
    public let recoverable: Bool
}

public struct ResponseEnvelope<T: Encodable>: Encodable {
    public let id: String
    public let type: String
    public let payload: T
}
