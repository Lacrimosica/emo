// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EmoKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EmoKit", targets: ["EmoKit"]),
    ],
    targets: [
        .target(name: "EmoKit"),
        .testTarget(name: "EmoKitTests", dependencies: ["EmoKit"]),
    ]
)
