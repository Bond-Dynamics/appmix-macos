// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppMix",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "appmix", targets: ["appmix"]),
        .executable(name: "AppMixBar", targets: ["AppMixBar"]),
    ],
    dependencies: [
        // In-app updates (BOND-224). Pinned exactly: a new Sparkle is a reviewed change, not a resolve.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "MixerCore"),
        .executableTarget(name: "appmix", dependencies: ["MixerCore"]),
        .executableTarget(
            name: "AppMixBar",
            dependencies: ["MixerCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "MixerCoreTests", dependencies: ["MixerCore"]),
    ]
)
