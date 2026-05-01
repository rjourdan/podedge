// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PodedgeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PodedgeCore", targets: ["PodedgeCore"]),
    ],
    targets: [
        .target(
            name: "PodedgeCore",
            path: "Sources/PodedgeCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PodedgeCoreTests",
            dependencies: ["PodedgeCore"],
            path: "Tests/PodedgeCoreTests",
            exclude: ["Fixtures"]
        ),
    ]
)
