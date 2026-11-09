import Foundation

/// The camera body grouping separates photos by (G1's Grouping row, PRD Similar groups step 1).
///
/// G1's grouping item keys a body by its model plus the body serial when the file carries one,
/// and falls back to the model alone when it does not. Two bodies of the same model shooting
/// the same scene at the same moment are unsupported, so a model without a serial is its own
/// bucket: it never joins the same model with a serial, and no extra logic, UI or setting covers
/// the ambiguous case (G1 §5, PRD Similar groups step 1).
public struct CameraBody: Hashable, Sendable {
    /// The trimmed, case-folded camera model used as the grouping key (PRD Similar groups step 1).
    /// This is a comparison key, not a display value.
    public let model: String

    /// The trimmed, case-folded body serial, or nil when the file carries none (G1 Grouping row).
    /// A blank or whitespace-only serial is treated as missing.
    public let serial: String?

    /// Keys a body from the metadata reader's model and serial values (G1 Grouping row).
    ///
    /// Returns nil when there is no usable model. PRD Similar groups only excludes photos
    /// without a capture time, so C9 extends that rule to model-less files: grouping never
    /// guesses a body, and the photo stays ungrouped.
    public init?(model: String?, serial: String? = nil) {
        guard let model = Self.key(model) else { return nil }
        self.model = model
        self.serial = Self.key(serial)
    }

    /// Trims surrounding whitespace and folds case, because S5 saw both differ across formats.
    private static func key(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed.lowercased()
    }
}
