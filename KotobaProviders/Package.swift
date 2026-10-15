// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error)
]

// Cloud speech-to-text routes behind KotobaCore's `TranscriptionProvider`. Foundation and os only (lint-enforced),
// so `swift test` covers request building and response parsing without the app.
let package = Package(
    name: "KotobaProviders",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KotobaProviders", targets: ["KotobaProviders"])
    ],
    dependencies: [
        .package(path: "../KotobaCore")
    ],
    targets: [
        .target(
            name: "KotobaProviders",
            dependencies: ["KotobaCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "KotobaProvidersTests",
            dependencies: ["KotobaProviders"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ]
)
