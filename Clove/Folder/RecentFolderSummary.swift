import CloveCore
import Foundation

/// The fields PRD P0-02 shows for one Recents entry, as plain text.
///
/// PRD P0-02 asks for a path summary, media type, photo count and last-opened time. The path
/// summary is the record's own text, so this type only turns the other three into words.
///
/// Design placeholder: U7 owns the copy for every failure and status line; these words only name
/// what the record holds, and a partial scan says the count is a lower bound (PRD P0-01).
enum RecentFolderSummary {
    /// The media type, photo count and last-opened time, joined for one row (PRD P0-02).
    static func detail(for recent: RecentFolder) -> String {
        [
            mediaTypeText(recent.mediaType), photoCountText(recent),
            lastOpenedText(recent.lastOpened),
        ]
        .joined(separator: " · ")
    }

    /// How the record's volume reads to the user (PRD P0-02; G1 decision 7).
    static func mediaTypeText(_ mediaType: FolderMediaType) -> String {
        switch mediaType {
        case .internalVolume: "Device storage"
        case .externalDrive: "External drive"
        case .cloudProvider: "Files provider"
        case .unknown: "Unknown location"
        }
    }

    /// The count from the last successful scan, or that no scan has run yet (PRD P0-02).
    ///
    /// A partial scan shows "at least", because PRD P0-01 never reports a shorter folder as a
    /// complete scan.
    static func photoCountText(_ recent: RecentFolder) -> String {
        guard let count = recent.photoCount else { return "Not scanned yet" }
        switch recent.scanStatus {
        case .partial:
            return "At least \(count) photos"
        case .complete, nil:
            return count == 1 ? "1 photo" : "\(count) photos"
        }
    }

    /// When the folder last opened successfully (PRD P0-02).
    static func lastOpenedText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
