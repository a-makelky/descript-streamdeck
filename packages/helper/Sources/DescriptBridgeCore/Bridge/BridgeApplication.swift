import Foundation

public final class BridgeApplication {
    private let controller = DescriptController()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
    }

    public func runServer() throws {
        while let line = readLine() {
            guard !line.isEmpty else {
                continue
            }

            do {
                let request = try decoder.decode(BridgeRequest.self, from: Data(line.utf8))
                try writeResponse(for: request)
            } catch {
                try write(
                    envelope: ResponseEnvelope(
                        id: "unknown",
                        type: "error",
                        payload: ErrorPayload(
                            code: "invalid_request",
                            message: error.localizedDescription,
                            recoverable: true
                        )
                    )
                )
            }
        }
    }

    public func runCLI(arguments: [String]) throws {
        let command = arguments.first ?? "status"
        switch command {
        case "ping":
            try printCLI(
                ResponseEnvelope(
                    id: "cli",
                    type: "pong",
                    payload: PongPayload(
                        helperVersion: helperVersion,
                        protocolVersion: helperProtocolVersion
                    )
                )
            )
        case "status":
            try printCLI(
                ResponseEnvelope(
                    id: "cli",
                    type: "status",
                    payload: controller.currentStatus()
                )
            )
        case "debug":
            try printCLI(
                ResponseEnvelope(
                    id: "cli",
                    type: "debugSnapshot",
                    payload: controller.debugSnapshot()
                )
            )
        case "record":
            try printCLICommandResult(outcome: controller.record(options: CommandOptions()))
        case "pauseResume":
            try printCLICommandResult(outcome: controller.pauseResume(options: CommandOptions()))
        case "stop":
            try printCLICommandResult(outcome: controller.stop(options: CommandOptions()))
        case "open-permissions":
            let opened = controller.openAccessibilitySettings()
            try printCLI(
                ResponseEnvelope(
                    id: "cli",
                    type: "commandResult",
                    payload: CommandResultPayload(
                        ok: opened,
                        message: opened
                            ? "Opened Accessibility settings."
                            : "Could not open Accessibility settings.",
                        status: controller.currentStatus()
                    )
                )
            )
        default:
            throw NSError(
                domain: "DescriptBridge",
                code: 64,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unknown command: \(command)"
                ]
            )
        }
    }

    private func writeResponse(for request: BridgeRequest) throws {
        let options = request.payload ?? CommandOptions()

        switch request.type {
        case .ping:
            try write(
                envelope: ResponseEnvelope(
                    id: request.id,
                    type: "pong",
                    payload: PongPayload(
                        helperVersion: helperVersion,
                        protocolVersion: helperProtocolVersion
                    )
                )
            )
        case .getStatus:
            try write(
                envelope: ResponseEnvelope(
                    id: request.id,
                    type: "status",
                    payload: controller.currentStatus(options: options)
                )
            )
        case .record:
            try writeCommandResult(
                id: request.id,
                outcome: controller.record(options: options)
            )
        case .pauseResume:
            try writeCommandResult(
                id: request.id,
                outcome: controller.pauseResume(options: options)
            )
        case .stop:
            try writeCommandResult(
                id: request.id,
                outcome: controller.stop(options: options)
            )
        case .openPermissions:
            let opened = controller.openAccessibilitySettings()
            try write(
                envelope: ResponseEnvelope(
                    id: request.id,
                    type: "commandResult",
                    payload: CommandResultPayload(
                        ok: opened,
                        message: opened
                            ? "Opened Accessibility settings."
                            : "Could not open Accessibility settings.",
                        status: controller.currentStatus(options: options)
                    )
                )
            )
        case .debugSnapshot:
            try write(
                envelope: ResponseEnvelope(
                    id: request.id,
                    type: "debugSnapshot",
                    payload: controller.debugSnapshot()
                )
            )
        }
    }

    private func writeCommandResult(id: String, outcome: CommandOutcome) throws {
        try write(
            envelope: ResponseEnvelope(
                id: id,
                type: "commandResult",
                payload: CommandResultPayload(
                    ok: outcome.ok,
                    message: outcome.message,
                    status: outcome.status
                )
            )
        )
    }

    private func write<T: Encodable>(envelope: ResponseEnvelope<T>) throws {
        let data = try encoder.encode(envelope)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }

    private func printCLI<T: Encodable>(_ envelope: ResponseEnvelope<T>) throws {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }

    private func printCLICommandResult(outcome: CommandOutcome) throws {
        try printCLI(
            ResponseEnvelope(
                id: "cli",
                type: "commandResult",
                payload: CommandResultPayload(
                    ok: outcome.ok,
                    message: outcome.message,
                    status: outcome.status
                )
            )
        )
    }
}
