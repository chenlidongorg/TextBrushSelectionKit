// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextBrushSelectionKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "TextBrushSelectionKit",
            targets: ["TextBrushSelectionKit"]
        )
    ],
    targets: [
        .target(
            name: "TextBrushSelectionKit",
            resources: [.process("Resources")]
        )
    ]
)
