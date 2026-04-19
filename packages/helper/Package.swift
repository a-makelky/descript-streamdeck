// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DescriptBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "descript-bridge", targets: ["DescriptBridge"])
    ],
    targets: [
        .target(
            name: "DescriptBridgeCore",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "DescriptBridge",
            dependencies: ["DescriptBridgeCore"]
        )
    ]
)

