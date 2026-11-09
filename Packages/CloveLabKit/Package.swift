// swift-tools-version: 6.0

import PackageDescription

/// Every spike has its own module and test target, and shares `SpikeSupport`.
/// The `CloveSpikes` product carries all of them, so the app links one product
/// and a spike only adds files inside its own folders.
let spikeModules = [
    "SpikeS1Access",
    "SpikeS2Previews",
    "SpikeS3XMP",
    "SpikeS4Metadata",
    "SpikeS5Grouping",
    "SpikeS6Scan",
    "SpikeS7Duo",
]

let package = Package(
    name: "CloveSpikes",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CloveSpikes", targets: ["SpikeSupport"] + spikeModules)
    ],
    targets: [
        .target(name: "SpikeSupport"),
        .testTarget(name: "SpikeSupportTests", dependencies: ["SpikeSupport"]),
    ]
        + spikeModules.map { module in
            .target(name: module, dependencies: ["SpikeSupport"])
        }
        + spikeModules.map { module in
            .testTarget(name: "\(module)Tests", dependencies: [.target(name: module)])
        }
)
