// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DynamicNotch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DynamicNotch",
            path: "Sources/DynamicNotch",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
