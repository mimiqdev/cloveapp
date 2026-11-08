// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CloveCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CloveCore", targets: ["CloveCore"])
    ],
    targets: [
        .target(name: "CloveCore"),
        .testTarget(name: "CloveCoreTests", dependencies: ["CloveCore"]),
    ]
)
