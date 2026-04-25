// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeekixStore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PeekixStore", targets: ["PeekixStore"])
    ],
    targets: [
        .target(name: "PeekixStore")
    ]
)
