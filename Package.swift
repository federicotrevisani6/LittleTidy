// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LittleTidy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LittleTidyCore",
            targets: ["LittleTidyCore"]
        ),
        .executable(
            name: "LittleTidy",
            targets: ["LittleTidy"]
        ),
        .executable(
            name: "LittleTidyQA",
            targets: ["LittleTidyQA"]
        )
    ],
    targets: [
        .target(
            name: "LittleTidyCore"
        ),
        .executableTarget(
            name: "LittleTidy",
            dependencies: ["LittleTidyCore"]
        ),
        .executableTarget(
            name: "LittleTidyQA",
            dependencies: ["LittleTidyCore"]
        ),
        .testTarget(
            name: "LittleTidyCoreTests",
            dependencies: ["LittleTidyCore"]
        )
    ]
)
