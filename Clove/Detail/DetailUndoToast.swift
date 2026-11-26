import CloveCore
import Foundation

/// Transient high-regret Undo prompt shown in Detail only after batch `Reject N unmarked` or a
/// mark that hides the current photo from an active live filter.
struct DetailUndoToast: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case rejected
        case rated(Int)
        case clearedReject
        case clearedRating
        case labelled(LabelColour)
        case clearedLabel
        case customLabel(String)

        init?(change: MarkChange, previousMarks: PhotoMarks) {
            if let rating = change.rating {
                if rating == .rejected {
                    self = .rejected
                } else if let stars = rating.starCount {
                    self = .rated(stars)
                } else {
                    self = previousMarks.isRejected ? .clearedReject : .clearedRating
                }
            } else if let label = change.label {
                if let colour = label.colour {
                    self = .labelled(colour)
                } else if label.isClear {
                    self = .clearedLabel
                } else {
                    self = .customLabel(label.rawValue)
                }
            } else {
                return nil
            }
        }

        func localizedTitle(language: ResolvedAppLanguage) -> String {
            switch self {
            case .rejected:
                AppLocalization.string("Rejected", language: language)
            case .rated(let stars):
                AppLocalization.starCount(stars, language: language)
            case .clearedReject:
                AppLocalization.string("Cleared reject", language: language)
            case .clearedRating:
                AppLocalization.string("Unrated", language: language)
            case .labelled(let colour):
                AppLocalization.colourName(colour, language: language)
            case .clearedLabel:
                AppLocalization.string("No label", language: language)
            case .customLabel(let raw):
                raw
            }
        }
    }

    enum Kind: Equatable, Sendable {
        case rejectedBatch(count: Int)
        case hiddenByFilter(action: Action)
    }

    static let autoDismissDelay: Duration = .seconds(4)

    let id: UUID
    let kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    func localizedMessage(language: ResolvedAppLanguage) -> String {
        switch kind {
        case .rejectedBatch(let count):
            AppLocalization.format("Rejected %lld photos", language: language, Int64(count))
        case .hiddenByFilter(let action):
            AppLocalization.format(
                "%@ · hidden by filter", language: language,
                action.localizedTitle(language: language))
        }
    }
}
