// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeekixSession",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PeekixSession", targets: ["PeekixSession"])
    ],
    dependencies: [
        .package(path: "../PeekixCore")
    ],
    targets: [
        .target(
            name: "PeekixSession",
            dependencies: [
                .product(name: "PeekixCore", package: "PeekixCore")
            ]
        )
    ]
)
