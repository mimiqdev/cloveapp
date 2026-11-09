// swift-tools-version: 6.0

import PackageDescription

/// Every probe has its own module and test target, and shares `LabSupport`.
/// The `CloveLabKit` product carries all of them, so the app links one product
/// and a probe only adds files inside its own folders.
let probeModules = [
    "FolderAccessProbe",
    "PreviewProbe",
    "XMPProbe",
    "EmbeddedMetadataProbe",
    "GroupingProbe",
    "ScanProbe",
    "FoldStateProbe",
]

let package = Package(
    name: "CloveLabKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CloveLabKit", targets: ["LabSupport"] + probeModules)
    ],
    targets: [
        .target(name: "LabSupport"),
        .testTarget(name: "LabSupportTests", dependencies: ["LabSupport"]),
    ]
        + probeModules.map { module in
            .target(name: module, dependencies: ["LabSupport"])
        }
        + probeModules.map { module in
            .testTarget(name: "\(module)Tests", dependencies: [.target(name: module)])
        }
)
