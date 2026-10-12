// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ManyDisplays",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ManyDisplays",
            path: "Sources/ManyDisplays",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
