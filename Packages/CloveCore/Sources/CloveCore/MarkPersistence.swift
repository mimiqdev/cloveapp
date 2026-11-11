import Foundation

/// Where a mark is saved; callers route writes by destination rather than a sidecar Boolean.
/// G1 decisions 2 and 6 apply at launch; a later embedded-JPEG destination can extend this type.
public enum MarkDestination: Hashable, Sendable {
    /// Ratings, Reject and labels for RAW sets only (G1 decision 2).
    case xmpSidecar(URL)
    /// Ratings, Reject and labels for a standalone JPEG/HIF (G1 decision 6).
    case cloveStorage
}

/// Pure persistence policy shared by metadata, writes and reject moves (G1 decisions 2, 5–6).
/// Standalone embedded ratings/labels are read-only input, never a launch write destination.
///
/// Reject is the rating value −1, so it takes the rating's destination and never has a route
/// of its own (decision record `reject-as-rating.md`).
public struct MarkPersistence: Hashable, Sendable {
    /// Where a new rating, Reject included, is saved (G1 decisions 2 and 6).
    public let rating: MarkDestination
    /// Where a new label is saved (G1 decisions 2 and 6).
    public let label: MarkDestination

    /// Routes RAW marks to a resolved sidecar, or models a new extension-replacing destination.
    /// Existing spelling is reused when supplied; discovery remains the caller's job.
    /// G1 sidecar naming and PRD How marks reach disk, rules 3, 5 and 6.
    public init(for photo: PhotoSet) {
        let metadata: MarkDestination
        if photo.primary.format == .raw {
            metadata = .xmpSidecar(
                photo.sidecarURL
                    ?? photo.primary.url.deletingPathExtension().appendingPathExtension("xmp"))
        } else {
            metadata = .cloveStorage
        }
        self.rating = metadata
        self.label = metadata
    }
}
