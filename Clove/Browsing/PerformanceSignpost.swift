import os

/// Shared signpost logs for Xcode Instruments (`xctrace`) comparisons across optimization passes.
enum PerformanceSignpost {
    static let subsystem = "com.mimiqdev.clove"
    static let gridCell = OSSignposter(subsystem: subsystem, category: "GridCell")
    static let detailArrival = OSSignposter(subsystem: subsystem, category: "DetailArrival")
    static let folderGrouping = OSSignposter(subsystem: subsystem, category: "FolderGrouping")
}
