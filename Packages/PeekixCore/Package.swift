// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Resolve absolute path to <repo-root>/Vendor/ffmpeg so that linker / header
// search paths work regardless of where SPM is invoked from (the package alone
// or a parent package that consumes it).
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let repoRoot = (packageDir as NSString).deletingLastPathComponent.deletingLastPathComponent
let ffmpegInclude = "\(repoRoot)/Vendor/ffmpeg/include"
let ffmpegLib = "\(repoRoot)/Vendor/ffmpeg/lib"

extension String {
    fileprivate var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
}

let package = Package(
    name: "PeekixCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PeekixCore", targets: ["PeekixCore"]),
        .executable(name: "peekix-smoke", targets: ["peekix-smoke"])
    ],
    targets: [
        .target(
            name: "CFFmpeg",
            path: "Sources/CFFmpeg",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I", ffmpegInclude])
            ]
        ),
        .target(
            name: "PeekixCore",
            dependencies: ["CFFmpeg"],
            swiftSettings: [
                .unsafeFlags(["-I", ffmpegInclude])
            ],
            linkerSettings: [
                .unsafeFlags(["-L", ffmpegLib]),
                .linkedLibrary("avformat"),
                .linkedLibrary("avcodec"),
                .linkedLibrary("avutil"),
                .linkedLibrary("swscale"),
                .linkedLibrary("swresample"),
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "peekix-smoke",
            dependencies: ["PeekixCore"]
        )
    ]
)
