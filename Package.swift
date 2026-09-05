// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LittleTidy",
    platforms: [
        .macOS(.v26)
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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "LittleTidyCore"
        ),
        .executableTarget(
            name: "LittleTidy",
            dependencies: [
                "LittleTidyCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("Resources")
            ]
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
