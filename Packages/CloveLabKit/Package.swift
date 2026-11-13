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
    "RAWDisplayProbe",
    "BrowsingPerformanceProbe",
]

/// Extra target dependencies for probes that reuse another probe's measurement code.
let extraDependencies: [String: [String]] = [
    "RAWDisplayProbe": ["PreviewProbe"]
]

/// Production packages measured directly by the current-app browsing flow.
let productionDependencies: [String: [Target.Dependency]] = [
    "BrowsingPerformanceProbe": [
        .product(name: "CloveCore", package: "CloveCore"),
        .product(name: "CloveImaging", package: "CloveImaging"),
    ]
]

let probeTargets: [Target] = probeModules.map { module in
    let extras = (extraDependencies[module] ?? []).map { Target.Dependency.target(name: $0) }
    return .target(
        name: module,
        dependencies: [.target(name: "LabSupport")] + extras
            + (productionDependencies[module] ?? []))
}

let probeTestTargets: [Target] = probeModules.map { module in
    let extras = (extraDependencies[module] ?? []).map { Target.Dependency.target(name: $0) }
    return .testTarget(name: "\(module)Tests", dependencies: [.target(name: module)] + extras)
}

let package = Package(
    name: "CloveLabKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CloveLabKit", targets: ["LabSupport"] + probeModules)
    ],
    dependencies: [
        .package(path: "../CloveCore"),
        .package(path: "../CloveImaging"),
    ],
    targets: [
        .target(name: "LabSupport"),
        .testTarget(name: "LabSupportTests", dependencies: ["LabSupport"]),
    ] + probeTargets + probeTestTargets
)
