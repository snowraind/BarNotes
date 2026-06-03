// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BarNotes",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BarNotes", targets: ["NotchNotes"])
    ],
    dependencies: [
        .package(path: "Vendor/swift-markdown-engine")
    ],
    targets: [
        .executableTarget(
            name: "NotchNotes",
            dependencies: [
                .product(name: "MarkdownEngine", package: "swift-markdown-engine")
            ],
            path: "Sources/NotchNotes"
        )
    ]
)
