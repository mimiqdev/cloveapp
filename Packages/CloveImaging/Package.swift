// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CloveImaging",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CloveImaging", targets: ["CloveImaging"])
    ],
    dependencies: [
        // Vendored as a git subtree from mimiqdev/focusmeta; see
        // docs/decisions/focusmeta-integration.md.
        .package(path: "../CloveFocusMetadata")
    ],
    targets: [
        .target(
            name: "CloveImaging",
            dependencies: [.product(name: "CameraFocusMetadata", package: "CloveFocusMetadata")]),
        .testTarget(name: "CloveImagingTests", dependencies: ["CloveImaging"]),
    ]
)
