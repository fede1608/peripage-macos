// swift-tools-version:6.0
import PackageDescription

let swift5: [SwiftSetting] = [.unsafeFlags(["-swift-version", "5"])]

let package = Package(
    name: "PeriPrint",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PeriPrint", targets: ["PeriPrint"]),
        .executable(name: "peripage", targets: ["peripage-cli"]),
        .executable(name: "PeriPrintDriver", targets: ["PeriPrintDriver"]),
        .library(name: "PeriPageKit", targets: ["PeriPageKit"]),
    ],
    targets: [
        // Protocol, Bluetooth transport, 1-bit image pipeline.
        .target(
            name: "PeriPageKit",
            swiftSettings: swift5,
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        // AppKit text rendering, decorative frames and other shared 1-bit drawing helpers.
        .target(name: "PeriRender", dependencies: ["PeriPageKit"], swiftSettings: swift5),
        // Procedurally generated printable puzzles and games.
        .target(name: "PuzzleKit", dependencies: ["PeriPageKit", "PeriRender"], swiftSettings: swift5),
        // Instagram / X post fetching, in-app capture browser and post layouts.
        .target(
            name: "SocialKit",
            dependencies: ["PeriPageKit", "PeriRender"],
            swiftSettings: swift5,
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        // Online resources: icons, emoji, fonts, free images.
        .target(name: "ResourceStore", dependencies: ["PeriPageKit", "PeriRender"], swiftSettings: swift5),
        .executableTarget(
            name: "PeriPrint",
            dependencies: ["PeriPageKit", "PeriRender", "PuzzleKit", "SocialKit", "ResourceStore"],
            swiftSettings: swift5
        ),
        // Menu bar helper that exposes the printer to every app's print dialog (see driver/README.md).
        .executableTarget(
            name: "PeriPrintDriver",
            dependencies: ["PeriPageKit"],
            path: "driver/PeriPrintDriver",
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "peripage-cli",
            dependencies: ["PeriPageKit"],
            swiftSettings: swift5,
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                "-Xlinker", Context.packageDirectory + "/Resources/cli-Info.plist",
            ])]
        ),
        .testTarget(name: "PeriPageKitTests", dependencies: ["PeriPageKit"], swiftSettings: swift5),
        .testTarget(name: "PuzzleKitTests", dependencies: ["PuzzleKit"], swiftSettings: swift5),
        .testTarget(name: "PeriPrintDriverTests", dependencies: ["PeriPrintDriver"], swiftSettings: swift5),
        .testTarget(name: "SocialKitTests", dependencies: ["SocialKit"], swiftSettings: swift5),
        .testTarget(name: "ResourceStoreTests", dependencies: ["ResourceStore"], swiftSettings: swift5),
    ]
)
