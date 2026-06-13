// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacCleanerCore",
            targets: ["MacCleanerCore"]
        ),
        .executable(
            name: "MacCleaner",
            targets: ["MacCleaner"]
        ),
        .executable(
            name: "MacCleanerQA",
            targets: ["MacCleanerQA"]
        )
    ],
    targets: [
        .target(
            name: "MacCleanerCore"
        ),
        .executableTarget(
            name: "MacCleaner",
            dependencies: ["MacCleanerCore"]
        ),
        .executableTarget(
            name: "MacCleanerQA",
            dependencies: ["MacCleanerCore"]
        ),
        .testTarget(
            name: "MacCleanerCoreTests",
            dependencies: ["MacCleanerCore"]
        )
    ]
)
