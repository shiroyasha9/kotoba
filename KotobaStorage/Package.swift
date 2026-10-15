// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error)
]

// System SQLite storage the app reads and writes, and the Wispr Flow import. Foundation, os, SQLite3 and KotobaCore
// only (lint-enforced), so `swift test` covers it against fixture databases without the app.
let package = Package(
    name: "KotobaStorage",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KotobaStorage", targets: ["KotobaStorage"])
    ],
    dependencies: [
        .package(path: "../KotobaCore")
    ],
    targets: [
        .target(
            name: "KotobaStorage",
            dependencies: ["KotobaCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "KotobaStorageTests",
            dependencies: ["KotobaStorage"],
            swiftSettings: swiftSettings
        ),
    ]
)
