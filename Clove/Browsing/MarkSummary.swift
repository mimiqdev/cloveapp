import CloveCore

/// A one-line summary of a photo's marks for the placeholder screens (PRD P0-05).
///
/// Design placeholder: the grid cell overlays and the detail marking bar show marks in place of
/// this text.
enum MarkSummary {
    /// The rating, colour label and Reject a photo carries, or `Unmarked` when it has none.
    static func text(for marks: PhotoMarks) -> String {
        var parts: [String] = []
        if marks.rating > .unrated { parts.append("\(marks.rating.rawValue) stars") }
        if let colour = marks.label.colour {
            parts.append(colour.rawValue)
        } else if !marks.label.isClear {
            // An unknown external label is still a label (PRD How marks reach disk, rule 9).
            parts.append(marks.label.rawValue)
        }
        if marks.isRejected { parts.append("Rejected") }
        return parts.isEmpty ? "Unmarked" : parts.joined(separator: " · ")
    }
}
