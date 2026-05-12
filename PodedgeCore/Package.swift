// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PodedgeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PodedgeCore", targets: ["PodedgeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.2"),
    ],
    targets: [
        .target(
            name: "PodedgeCore",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ],
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
