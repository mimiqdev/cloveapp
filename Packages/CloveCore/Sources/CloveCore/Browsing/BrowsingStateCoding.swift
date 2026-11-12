import Foundation

extension BrowsingState {
    /// The encoded form's version, which a scene writes and reads back (PRD P0-14).
    ///
    /// Version 1 is the only shape this release understands. A launch reads it from the scene's
    /// storage, so the form is treated as untrusted input: anything this version cannot read
    /// exactly starts at entry rather than stopping the launch (PRD P0-14). Adding an optional
    /// field keeps version 1 and decodes it as absent; any other change to what an existing field
    /// means takes a new version and starts old scenes at entry.
    public static let encodedVersion = 1

    /// Encodes the state for one scene to store (PRD P0-14).
    ///
    /// Returns nil only when the value cannot be encoded at all; the caller then stores nothing
    /// and the next launch starts at entry.
    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Reads a scene's stored state, or entry when there is nothing usable (PRD P0-14).
    ///
    /// Missing data, unreadable data, a form from another version and a spelling this release
    /// does not know all return ``BrowsingState/entry``. The restored value still needs
    /// ``BrowsingState/restored(from:)`` before a screen reads it, because the folder it names
    /// may have changed.
    public static func decoded(from data: Data?) -> BrowsingState {
        guard let data, let state = try? JSONDecoder().decode(BrowsingState.self, from: data)
        else { return .entry }
        return state
    }
}

/// The versioned wire format, so the type is `Codable` and a caller that decodes it directly still
/// gets the version check (PRD P0-14).
extension BrowsingState {
    /// Reads the versioned form, refusing a form this release cannot read exactly.
    ///
    /// Decoding throws here; ``BrowsingState/decoded(from:)`` is the launch path that turns any
    /// refusal into entry.
    public init(from decoder: any Decoder) throws {
        let form = try EncodedBrowsingState(from: decoder)
        guard let state = form.state else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Browsing state form version \(form.version) is not readable")
            )
        }
        self = state
    }

    /// Writes the versioned form a scene stores (PRD P0-14).
    public func encode(to encoder: any Encoder) throws {
        try EncodedBrowsingState(self).encode(to: encoder)
    }
}

/// The versioned form a scene stores; the only shape ``BrowsingState/encodedVersion`` writes.
private struct EncodedBrowsingState: Codable {
    var version: Int
    var folder: String?
    var currentPhoto: EncodedPhoto?
    var filter: EncodedFilter
    var order: String
    var selection: [EncodedPhoto]
    var route: String

    init(_ state: BrowsingState) {
        version = BrowsingState.encodedVersion
        folder = state.folder?.rawValue
        currentPhoto = state.currentPhoto.map(EncodedPhoto.init)
        filter = EncodedFilter(state.filter)
        order = state.order.encodedSpelling
        // The selection is unordered; sorting keeps the bytes stable for the same set.
        selection = state.selection
            .map(EncodedPhoto.init)
            .sorted { ($0.folder, $0.path, $0.stem) < ($1.folder, $1.path, $1.stem) }
        route = state.route.encodedSpelling
    }

    /// The state this form describes, or nil when it is not exactly readable.
    var state: BrowsingState? {
        guard version == BrowsingState.encodedVersion,
            let route = BrowserRoute(encodedSpelling: route),
            let order = PhotoOrder(encodedSpelling: order),
            let filter = filter.filter
        else { return nil }
        return BrowsingState(
            folder: folder.map { FolderIdentity(rawValue: $0) },
            currentPhoto: currentPhoto?.photo,
            filter: filter,
            order: order,
            selection: Set(selection.map(\.photo)),
            route: route)
    }
}

/// One photo identity in the stored form (PRD P0-01: the parts that make it stable).
private struct EncodedPhoto: Codable, Hashable {
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

/// The grid filter in the stored form, with the rating minimum only where it applies
/// (PRD P0-03).
private struct EncodedFilter: Codable {
    var kind: String
    var minimum: Int?
    var path: String?

    init(_ filter: PhotoFilter) {
        kind = filter.encodedSpelling
        if case .ratedAtLeast(let rating) = filter { minimum = rating.rawValue }
        if case .subfolder(let folderPath) = filter { path = folderPath }
    }

    var filter: PhotoFilter? {
        switch kind {
        case "all": return .all
        case "unmarked": return .unmarked
        case "rejected": return .rejected
        case "subfolder":
            guard let path else { return nil }
            return .subfolder(path)
        case "ratedAtLeast":
            // Reject is −1 and unrated is 0, so neither can be a star minimum (PRD P0-03).
            guard let minimum, minimum > Rating.unrated.rawValue,
                let rating = Rating(rawValue: minimum)
            else { return nil }
            return .ratedAtLeast(rating)
        default: return nil
        }
    }
}

private extension PhotoFilter {
    var encodedSpelling: String {
        switch self {
        case .all: "all"
        case .unmarked: "unmarked"
        case .rejected: "rejected"
        case .ratedAtLeast: "ratedAtLeast"
        case .subfolder: "subfolder"
        }
    }
}

private extension PhotoOrder {
    var encodedSpelling: String {
        switch self {
        case .captureTime: "captureTime"
        case .fileName: "fileName"
        }
    }

    init?(encodedSpelling: String) {
        switch encodedSpelling {
        case "captureTime": self = .captureTime
        case "fileName": self = .fileName
        default: return nil
        }
    }
}

private extension BrowserRoute {
    var encodedSpelling: String {
        switch self {
        case .entry: "entry"
        case .grid: "grid"
        case .detail: "detail"
        case .settings: "settings"
        }
    }

    init?(encodedSpelling: String) {
        switch encodedSpelling {
        case "entry": self = .entry
        case "grid": self = .grid
        case "detail": self = .detail
        case "settings": self = .settings
        default: return nil
        }
    }
}
