import Testing

import CloveCore

/// Fixtures for the marking-input tests: one folder, simple identities, no real files.
enum MarkingFixtures {
    static let folderID = FolderIdentity(rawValue: "marking-input-tests")

    /// A validated star count, failing the test rather than trapping on an invalid value.
    static func stars(_ value: Int) throws -> Rating {
        try #require(Rating(rawValue: value))
    }

    /// The enabled levels for the listed star counts.
    static func enabled(_ values: Int...) throws -> EnabledRatings {
        let levels = try values.map(stars)
        return try #require(EnabledRatings(levels))
    }

    /// Marks built from plain values, so tests read like product states.
    static func marks(
        stars value: Int = 0,
        label: LabelColour? = nil,
        rejected: Bool = false
    ) throws -> PhotoMarks {
        PhotoMarks(
            rating: try stars(value),
            label: label.map { ColourLabel(colour: $0) } ?? .clear,
            isRejected: rejected)
    }

    /// A photo in the test folder's root; the ordering time is irrelevant to these rules.
    static func photo(_ stem: String, marks: PhotoMarks = PhotoMarks()) -> GridPhoto {
        GridPhoto(
            id: photoID(stem),
            fileName: "\(stem).ARW",
            time: .unavailable,
            marks: marks)
    }

    static func photoID(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(folderID: folderID, relativeFolderPath: "", stem: stem)
    }
}
