import Foundation

/// The last confirmed culling progress kept with Recents (handoff screens.md, Entry).
/// Rejected photos count as decided even when they also carry a rating or label (G1 §2.5).
public struct FolderProgress: Codable, Hashable, Sendable {
    /// Rated or labelled photos, excluding rejects (handoff Entry progress line).
    public let marked: Int
    /// Rejected photos, counted once (handoff Entry progress line).
    public let rejected: Int
    /// Logical photos in the folder, never files (PRD P0-02).
    public let total: Int
    /// Whether the totals originated in a complete scan. Partial scans retain those totals
    /// while applying this session's confirmed changes (handoff Entry; PRD P0-08).
    public let isComplete: Bool
    private let allowsFinished: Bool
    /// The last viewed photo, independent of its mark or save state (handoff Entry).
    public let lastViewedPhoto: PhotoIdentity?
    /// Up to three identities used for the folder's cached thumbnail strip (handoff Entry).
    public let previewPhotos: [PhotoIdentity]

    /// Stores bounded, mutually exclusive counts (handoff Entry; PRD P0-02).
    public init(
        marked: Int, rejected: Int, total: Int, isComplete: Bool = true,
        lastViewedPhoto: PhotoIdentity? = nil, previewPhotos: [PhotoIdentity] = [],
        allowsFinished: Bool? = nil
    ) {
        self.allowsFinished = allowsFinished ?? isComplete
        self.total = max(0, total)
        self.rejected = min(max(0, rejected), self.total)
        self.marked = min(max(0, marked), self.total - self.rejected)
        self.isComplete = isComplete
        self.lastViewedPhoto = lastViewedPhoto
        self.previewPhotos = Array(previewPhotos.prefix(3))
    }

    /// Counts confirmed marks only; callers never include a pending request (PRD P0-08).
    public init(
        confirmedMarks: [PhotoMarks], isComplete: Bool,
        lastViewedPhoto: PhotoIdentity? = nil, previewPhotos: [PhotoIdentity] = []
    ) {
        self.init(
            marked: confirmedMarks.filter {
                !$0.isRejected && ($0.rating != .unrated || !$0.label.isClear)
            }.count,
            rejected: confirmedMarks.filter(\.isRejected).count,
            total: confirmedMarks.count, isComplete: isComplete,
            lastViewedPhoto: lastViewedPhoto, previewPhotos: previewPhotos)
    }

    /// One photo's first and latest confirmed marks in the current session (PRD P0-08).
    public struct ConfirmedChange: Hashable, Sendable {
        public let before: PhotoMarks
        public let after: PhotoMarks
        /// A partial rescan cannot reassert Done while a decided photo is now unmarked.
        public var becameUnmarked: Bool { Self.decided(before) && !Self.decided(after) }

        public init(before: PhotoMarks, after: PhotoMarks) {
            self.before = before
            self.after = after
        }

        /// Keeps the session's baseline and takes the latest confirmed marks.
        public func updating(to marks: PhotoMarks) -> ConfirmedChange {
            ConfirmedChange(before: before, after: marks)
        }

        private static func decided(_ marks: PhotoMarks) -> Bool {
            marks.isRejected || marks.rating != .unrated || !marks.label.isClear
        }
    }

    /// Keeps previous totals on a partial scan and applies net confirmed changes once per photo.
    /// Unread XMP never contributes new left counts (handoff Entry; PRD P0-02, P0-08).
    public static func snapshot(
        confirmedMarks: [PhotoMarks], scanIsComplete: Bool, previous: FolderProgress?,
        lastViewedPhoto: PhotoIdentity?, previewPhotos: [PhotoIdentity],
        confirmedChanges: [PhotoIdentity: ConfirmedChange] = [:]
    ) -> FolderProgress {
        if scanIsComplete {
            return FolderProgress(
                confirmedMarks: confirmedMarks, isComplete: true,
                lastViewedPhoto: lastViewedPhoto, previewPhotos: previewPhotos)
        }
        var marked = previous?.marked ?? 0
        var rejected = previous?.rejected ?? 0
        for change in confirmedChanges.values {
            marked += Self.marked(change.after) - Self.marked(change.before)
            rejected += (change.after.isRejected ? 1 : 0) - (change.before.isRejected ? 1 : 0)
        }
        return FolderProgress(
            marked: marked, rejected: rejected,
            total: previous?.total ?? 0, isComplete: previous?.isComplete ?? false,
            lastViewedPhoto: lastViewedPhoto ?? previous?.lastViewedPhoto,
            previewPhotos: previous?.previewPhotos ?? previewPhotos,
            allowsFinished: previous?.finished == true
                && !confirmedChanges.values.contains(where: \.becameUnmarked))
    }

    private static func marked(_ marks: PhotoMarks) -> Int {
        !marks.isRejected && (marks.rating != .unrated || !marks.label.isClear) ? 1 : 0
    }

    /// Reads bounded counts and optional resume information (handoff Entry; PRD P0-02).
    public init(from decoder: any Decoder) throws {
        let form = try Form(from: decoder)
        self.init(
            marked: form.marked, rejected: form.rejected, total: form.total,
            isComplete: form.isComplete, lastViewedPhoto: form.lastViewedPhoto?.photo,
            previewPhotos: (form.previewPhotos ?? []).map(\.photo),
            allowsFinished: form.allowsFinished)
    }

    /// Persists identities as folder, relative path and stem, never a permission (G1 access).
    public func encode(to encoder: any Encoder) throws {
        try Form(
            marked: marked, rejected: rejected, total: total, isComplete: isComplete,
            lastViewedPhoto: lastViewedPhoto.map(StoredPhoto.init),
            previewPhotos: previewPhotos.map(StoredPhoto.init), allowsFinished: allowsFinished
        ).encode(to: encoder)
    }

    private struct Form: Codable {
        var marked: Int
        var rejected: Int
        var total: Int
        var isComplete: Bool
        var lastViewedPhoto: StoredPhoto?
        var previewPhotos: [StoredPhoto]?
        var allowsFinished: Bool?
    }

    private struct StoredPhoto: Codable {
        var folder: String
        var path: String
        var stem: String

        init(_ photo: PhotoIdentity) {
            folder = photo.folderID.rawValue
            path = photo.relativeFolderPath
            stem = photo.stem
        }

        var photo: PhotoIdentity {
            PhotoIdentity(
                folderID: FolderIdentity(rawValue: folder), relativeFolderPath: path, stem: stem)
        }
    }

    /// Photos still undecided, never negative (handoff Entry).
    public var left: Int { max(0, total - marked - rejected) }
    /// Done follows a complete scan, or preserves an existing Done state during a partial scan
    /// only if no confirmed edit became unmarked (handoff Entry).
    public var finished: Bool { isComplete && allowsFinished && total > 0 && left == 0 }
}
