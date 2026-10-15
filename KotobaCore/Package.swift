// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "KotobaCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KotobaCore", targets: ["KotobaCore"])
    ],
    targets: [
        .target(name: "KotobaCore", swiftSettings: swiftSettings),
        .testTarget(
            name: "KotobaCoreTests",
            dependencies: ["KotobaCore"],
            swiftSettings: swiftSettings
        ),
    ]
)
