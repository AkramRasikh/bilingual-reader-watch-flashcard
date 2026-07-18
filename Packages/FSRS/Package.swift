// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FSRS",
    platforms: [
        .iOS(.v14),
        .watchOS(.v7),
        .macOS(.v10_13),
    ],
    products: [
        .library(name: "FSRS", targets: ["FSRS"]),
    ],
    targets: [
        .target(
            name: "FSRS",
            path: "Sources/FSRS"
        ),
    ]
)
