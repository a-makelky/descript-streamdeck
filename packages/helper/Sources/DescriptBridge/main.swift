import DescriptBridgeCore

@main
struct DescriptBridgeMain {
    static func main() throws {
        let app = BridgeApplication()
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.isEmpty {
            try app.runServer()
            return
        }

        try app.runCLI(arguments: arguments)
    }
}

