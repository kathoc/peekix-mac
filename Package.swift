// swift-tools-version: 5.9
// Top-level Swift package for the walking-skeleton verification path.
//
// The shippable build target is App/Peekix.xcodeproj. This package exists so
// that the same source tree can be compiled and link-verified with `swift build`
// (e.g. `otool -L .build/arm64-apple-macosx/debug/Peekix`) without requiring
// a working Xcode IDE installation. It is not packaged or distributed.
import PackageDescription

let package = Package(
    name: "Peekix",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Peekix", targets: ["Peekix"])
    ],
    dependencies: [
        .package(path: "Packages/PeekixCore"),
        .package(path: "Packages/PeekixSession"),
        .package(path: "Packages/PeekixUI"),
        .package(path: "Packages/PeekixStore")
    ],
    targets: [
        .executableTarget(
            name: "Peekix",
            dependencies: [
                .product(name: "PeekixCore", package: "PeekixCore"),
                .product(name: "PeekixSession", package: "PeekixSession"),
                .product(name: "PeekixUI", package: "PeekixUI"),
                .product(name: "PeekixStore", package: "PeekixStore")
            ],
            path: "App/Peekix",
            exclude: [
                "Info.plist",
                "Peekix.entitlements",
                "Assets.xcassets"
            ]
        )
    ]
)
