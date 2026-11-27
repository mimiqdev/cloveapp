import CloveCore
import Foundation

/// Transient completion prompt shown in Detail when a mark transitions the open folder's
/// placed photos from having unmarked photos to zero unmarked photos.
struct DetailAllReviewedToast: Equatable, Sendable {
    let id: UUID
    let totalCount: Int

    init(id: UUID = UUID(), totalCount: Int) {
        self.id = id
        self.totalCount = max(totalCount, 0)
    }

    func localizedMessage(language: ResolvedAppLanguage) -> String {
        AppLocalization.format("All %lld reviewed", language: language, Int64(totalCount))
    }

    func localizedActionTitle(language: ResolvedAppLanguage) -> String {
        AppLocalization.string("Back to Grid", language: language)
    }
}
