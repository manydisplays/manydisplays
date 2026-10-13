// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ManyDisplays",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ManyDisplays", targets: ["ManyDisplays"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Everything lives in the library so it can be unit-tested; the executable is a stub.
        .target(
            name: "ManyDisplaysCore",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ManyDisplaysCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "ManyDisplays",
            dependencies: ["ManyDisplaysCore"],
            path: "Sources/ManyDisplays",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ManyDisplaysCoreTests",
            dependencies: ["ManyDisplaysCore"],
            path: "Tests/ManyDisplaysCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
