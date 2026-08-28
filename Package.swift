// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KLRichTextEngine",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "KLRichTextEngine",
            targets: ["KLRichTextEngine"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-docc-plugin",
            from: "1.5.0"
        ),
    ],
    targets: [
        .target(
            name: "KLRichTextEngine",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KLRichTextEngineTests",
            dependencies: ["KLRichTextEngine"],
            resources: [.process("Fixtures")]
        ),
    ]
)
