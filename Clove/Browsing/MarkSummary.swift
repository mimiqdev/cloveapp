import CloveCore

/// A photo's mark summary for VoiceOver, filmstrip thumbnails and the read-only Info sheet.
enum MarkSummary {
    /// The rating, colour label and Reject a photo carries, or `Unmarked` when it has none.
    static func text(for marks: PhotoMarks, language: ResolvedAppLanguage = .english) -> String {
        var parts: [String] = []
        if let stars = marks.rating.starCount {
            parts.append(AppLocalization.starCount(stars, language: language))
        }
        if let colour = marks.label.colour {
            parts.append(AppLocalization.colourName(colour, language: language))
        } else if !marks.label.isClear {
            // An unknown external label is still a label (PRD How marks reach disk, rule 9).
            parts.append(marks.label.rawValue)
        }
        if marks.isRejected { parts.append(AppLocalization.string("Rejected", language: language)) }
        return parts.isEmpty
            ? AppLocalization.string("Unmarked", language: language)
            : parts.joined(separator: " · ")
    }
}
