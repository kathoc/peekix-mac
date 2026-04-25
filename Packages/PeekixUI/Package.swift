// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeekixUI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PeekixUI", targets: ["PeekixUI"])
    ],
    dependencies: [
        .package(path: "../PeekixSession"),
        .package(path: "../PeekixStore")
    ],
    targets: [
        .target(
            name: "PeekixUI",
            dependencies: [
                .product(name: "PeekixSession", package: "PeekixSession"),
                .product(name: "PeekixStore", package: "PeekixStore")
            ]
        )
    ]
)
