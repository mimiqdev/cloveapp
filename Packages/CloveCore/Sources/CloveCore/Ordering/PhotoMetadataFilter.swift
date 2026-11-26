import Foundation

/// Fixed photographer focal-length buckets covering all positive focal lengths without gaps.
public enum FocalLengthBucket: String, CaseIterable, Hashable, Sendable, Codable {
    case ultraWide
    case wide
    case standard
    case shortTelephoto
    case telephoto

    /// Classifies a positive finite focal length in millimetres into one of five fixed buckets.
    public init?(millimetres: Double) {
        guard millimetres.isFinite, millimetres > 0 else { return nil }
        if millimetres < 24 {
            self = .ultraWide
        } else if millimetres < 36 {
            self = .wide
        } else if millimetres < 71 {
            self = .standard
        } else if millimetres <= 135 {
            self = .shortTelephoto
        } else {
            self = .telephoto
        }
    }

    /// Fixed technical millimetre range label shown alongside the localized bucket name.
    public var rangeLabel: String {
        switch self {
        case .ultraWide: "< 24 mm"
        case .wide: "24–35 mm"
        case .standard: "36–70 mm"
        case .shortTelephoto: "71–135 mm"
        case .telephoto: "> 135 mm"
        }
    }
}

/// Lightweight camera, lens, and focal-length metadata captured during the existing scan pass.
public struct PhotoFilterMetadata: Hashable, Sendable {
    public var camera: String?
    public var lens: String?
    /// Preferred focal length in millimetres (35mm-equivalent when present and valid, else actual).
    public var focalLengthMillimetres: Double?

    public static let empty = PhotoFilterMetadata()

    public init(
        camera: String? = nil,
        lens: String? = nil,
        focalLengthMillimetres: Double? = nil
    ) {
        self.camera = Self.normalizedText(camera)
        self.lens = Self.normalizedText(lens)
        if let focalLengthMillimetres, focalLengthMillimetres.isFinite, focalLengthMillimetres > 0 {
            self.focalLengthMillimetres = focalLengthMillimetres
        } else {
            self.focalLengthMillimetres = nil
        }
    }

    public var focalLengthBucket: FocalLengthBucket? {
        focalLengthMillimetres.flatMap(FocalLengthBucket.init(millimetres:))
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// Single-select secondary filter criteria combined with AND across dimensions and primary filters.
public struct PhotoMetadataFilter: Hashable, Sendable, Codable {
    public var camera: String?
    public var lens: String?
    public var focalLength: FocalLengthBucket?
    public var keyword: String?

    public static let none = PhotoMetadataFilter()

    public init(
        camera: String? = nil,
        lens: String? = nil,
        focalLength: FocalLengthBucket? = nil,
        keyword: String? = nil
    ) {
        self.camera = Self.normalizedText(camera)
        self.lens = Self.normalizedText(lens)
        self.focalLength = focalLength
        self.keyword = Self.normalizedText(keyword)
    }

    public var isEmpty: Bool {
        camera == nil && lens == nil && focalLength == nil && keyword == nil
    }

    public var activeCount: Int {
        (camera != nil ? 1 : 0)
            + (lens != nil ? 1 : 0)
            + (focalLength != nil ? 1 : 0)
            + (keyword != nil ? 1 : 0)
    }

    /// Whether a photo satisfies every active metadata and keyword criterion.
    public func matches(_ photo: GridPhoto) -> Bool {
        matches(metadata: photo.metadata, keywords: photo.marks.keywords)
    }

    /// Whether metadata and keywords satisfy every active criterion.
    public func matches(metadata: PhotoFilterMetadata, keywords: [String]) -> Bool {
        if let camera, metadata.camera != camera { return false }
        if let lens, metadata.lens != lens { return false }
        if let focalLength, metadata.focalLengthBucket != focalLength { return false }
        if let keyword, !keywords.contains(keyword) { return false }
        return true
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// One selectable value in a metadata or keyword filter dimension together with its folder count.
public struct PhotoFilterOption<Value: Hashable & Sendable>: Hashable, Sendable {
    public let value: Value
    public let count: Int

    public init(value: Value, count: Int) {
        self.value = value
        self.count = count
    }
}

/// Available metadata and keyword filter options derived from a folder's placed photos.
/// Camera, lens, and focal-length dimensions auto-hide when fewer than two distinct non-empty
/// values exist; keywords auto-hide when no photo has keywords or when every photo shares the exact
/// same single keyword.
public struct PhotoMetadataFilterOptions: Equatable, Sendable {
    public static let empty = PhotoMetadataFilterOptions(photos: [])

    public let cameras: [PhotoFilterOption<String>]
    public let lenses: [PhotoFilterOption<String>]
    public let focalLengths: [PhotoFilterOption<FocalLengthBucket>]
    public let keywords: [PhotoFilterOption<String>]

    public var hasAnyDimension: Bool {
        !cameras.isEmpty || !lenses.isEmpty || !focalLengths.isEmpty || !keywords.isEmpty
    }

    public init(photos: [GridPhoto]) {
        var cameraCounts: [String: Int] = [:]
        var lensCounts: [String: Int] = [:]
        var bucketCounts: [FocalLengthBucket: Int] = [:]
        var keywordCounts: [String: Int] = [:]

        for photo in photos {
            if let camera = photo.metadata.camera, !camera.isEmpty {
                cameraCounts[camera, default: 0] += 1
            }
            if let lens = photo.metadata.lens, !lens.isEmpty {
                lensCounts[lens, default: 0] += 1
            }
            if let bucket = photo.metadata.focalLengthBucket {
                bucketCounts[bucket, default: 0] += 1
            }
            let photoKeywords = photo.marks.keywords
            if photoKeywords.count == 1 {
                let keyword = photoKeywords[0]
                if !keyword.isEmpty {
                    keywordCounts[keyword, default: 0] += 1
                }
            } else if photoKeywords.count > 1 {
                for keyword in Set(photoKeywords) where !keyword.isEmpty {
                    keywordCounts[keyword, default: 0] += 1
                }
            }
        }

        cameras = Self.sortedAlphabeticalOptions(cameraCounts)
        lenses = Self.sortedAlphabeticalOptions(lensCounts)
        focalLengths =
            bucketCounts.count >= 2
            ? FocalLengthBucket.allCases.compactMap { bucket in
                guard let count = bucketCounts[bucket] else { return nil }
                return PhotoFilterOption(value: bucket, count: count)
            }
            : []
        let showsKeywords =
            keywordCounts.count >= 2
            || (keywordCounts.count == 1 && (keywordCounts.values.first ?? 0) < photos.count)
        keywords = showsKeywords ? Self.sortedByFrequencyOptions(keywordCounts) : []
    }

    private static func sortedAlphabeticalOptions(_ counts: [String: Int])
        -> [PhotoFilterOption<String>]
    {
        guard counts.count >= 2 else { return [] }
        return counts.keys
            .sorted { lhs, rhs in
                let comparison = lhs.localizedStandardCompare(rhs)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs < rhs
            }
            .map { PhotoFilterOption(value: $0, count: counts[$0, default: 0]) }
    }

    private static func sortedByFrequencyOptions(_ counts: [String: Int])
        -> [PhotoFilterOption<String>]
    {
        counts.keys
            .sorted { lhs, rhs in
                let lhsCount = counts[lhs, default: 0]
                let rhsCount = counts[rhs, default: 0]
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                let comparison = lhs.localizedStandardCompare(rhs)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs < rhs
            }
            .map { PhotoFilterOption(value: $0, count: counts[$0, default: 0]) }
    }
}
