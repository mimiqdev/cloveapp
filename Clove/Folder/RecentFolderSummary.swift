import CloveCore
import Foundation
import UIKit

/// Entry's display-only names and dates (handoff Entry; PRD P0-02).
enum RecentFolderSummary {
    static func name(for recent: RecentFolder) -> String {
        FolderDisplayLocation.name(path: recent.pathSummary)
    }

    static func location(for recent: RecentFolder) -> String {
        FolderDisplayLocation.text(
            path: recent.pathSummary, volumeName: recent.volumeName, mediaType: recent.mediaType,
            device: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func count(for recent: RecentFolder) -> String {
        let knownProgress = recent.progress.flatMap { $0.isComplete || $0.total > 0 ? $0 : nil }
        guard let count = knownProgress?.total ?? recent.photoCount else { return "" }
        let partial = knownProgress.map { !$0.isComplete } ?? (recent.scanStatus == .partial)
        return (partial ? "≥ " : "") + count.formatted()
    }
}
