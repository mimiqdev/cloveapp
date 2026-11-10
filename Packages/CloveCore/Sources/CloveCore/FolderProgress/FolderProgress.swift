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
    /// Whether the scan covered the whole folder; a partial scan cannot claim Done.
    public let isComplete: Bool
    /// The last viewed photo, independent of its mark or save state (handoff Entry).
    public let lastViewedPhoto: PhotoIdentity?
    /// Up to three identities used for the folder's cached thumbnail strip (handoff Entry).
    public let previewPhotos: [PhotoIdentity]

    /// Stores bounded, mutually exclusive counts (handoff Entry; PRD P0-02).
    public init(
        marked: Int, rejected: Int, total: Int, isComplete: Bool = true,
        lastViewedPhoto: PhotoIdentity? = nil, previewPhotos: [PhotoIdentity] = []
    ) {
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

    /// Reads bounded counts and optional resume information (handoff Entry; PRD P0-02).
    public init(from decoder: any Decoder) throws {
        let form = try Form(from: decoder)
        self.init(
            marked: form.marked, rejected: form.rejected, total: form.total,
            isComplete: form.isComplete, lastViewedPhoto: form.lastViewedPhoto?.photo,
            previewPhotos: (form.previewPhotos ?? []).map(\.photo))
    }

    /// Persists identities as folder, relative path and stem, never a permission (G1 access).
    public func encode(to encoder: any Encoder) throws {
        try Form(
            marked: marked, rejected: rejected, total: total, isComplete: isComplete,
            lastViewedPhoto: lastViewedPhoto.map(StoredPhoto.init),
            previewPhotos: previewPhotos.map(StoredPhoto.init)
        ).encode(to: encoder)
    }

    private struct Form: Codable {
        var marked: Int
        var rejected: Int
        var total: Int
        var isComplete: Bool
        var lastViewedPhoto: StoredPhoto?
        var previewPhotos: [StoredPhoto]?
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
    /// A fully read, nonempty folder with every photo decided (handoff Entry, Done).
    public var finished: Bool { isComplete && total > 0 && left == 0 }
}
