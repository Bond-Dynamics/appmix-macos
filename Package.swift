// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppMix",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "appmix", targets: ["appmix"]),
        .executable(name: "AppMixBar", targets: ["AppMixBar"]),
    ],
    targets: [
        .target(name: "MixerCore"),
        .executableTarget(name: "appmix", dependencies: ["MixerCore"]),
        .executableTarget(name: "AppMixBar", dependencies: ["MixerCore"]),
        .testTarget(name: "MixerCoreTests", dependencies: ["MixerCore"]),
    ]
)
