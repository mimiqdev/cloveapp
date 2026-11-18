import CloveCore
import Foundation
import UIKit

/// Entry's display-only names and dates (handoff Entry; PRD P0-02).
enum RecentFolderSummary {
    static func name(for recent: RecentFolder, language: ResolvedAppLanguage = .english) -> String {
        let name = FolderDisplayLocation.name(path: recent.pathSummary)
        if name == "Folder", URL(fileURLWithPath: recent.pathSummary).lastPathComponent != "Folder"
        {
            return AppLocalization.string("Folder", language: language)
        }
        return name
    }

    /// Reads the device idiom, so it runs on the main actor.
    @MainActor
    static func location(for recent: RecentFolder, language: ResolvedAppLanguage = .english)
        -> String
    {
        let raw = FolderDisplayLocation.text(
            path: recent.pathSummary, volumeName: recent.volumeName, mediaType: recent.mediaType,
            device: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        var parts = raw.components(separatedBy: " › ")
        if let first = parts.first,
            first == "iCloud Drive" || first == "On My iPhone" || first == "On My iPad"
        {
            parts[0] = AppLocalization.string(first, language: language)
        }
        return parts.joined(separator: " › ")
    }

    static func relativeDate(_ date: Date, language: ResolvedAppLanguage = .english) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        formatter.locale = language.locale
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func count(for recent: RecentFolder, language: ResolvedAppLanguage = .english) -> String
    {
        let knownProgress = recent.progress.flatMap { $0.isComplete || $0.total > 0 ? $0 : nil }
        guard let count = knownProgress?.total ?? recent.photoCount else { return "" }
        let partial = knownProgress.map { !$0.isComplete } ?? (recent.scanStatus == .partial)
        return (partial ? "≥ " : "") + count.formatted(.number.locale(language.locale))
    }
}
