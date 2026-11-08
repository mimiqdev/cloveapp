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
    targets: [
        .target(name: "CloveImaging"),
        .testTarget(name: "CloveImagingTests", dependencies: ["CloveImaging"]),
    ]
)
