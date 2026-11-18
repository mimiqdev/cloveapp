import CloveCore
import Observation
import SwiftUI

/// The top-level categories of the Settings screen (issue #264, #325).
enum SettingsCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case appearance
    case language
    case cullingAndMarking
    case browsingAndGroups
    case photoDisplay
    case moveRejects

    var id: String { rawValue }

    var title: String {
        title(language: .english)
    }

    func title(language: ResolvedAppLanguage) -> String {
        switch self {
        case .appearance: AppLocalization.string("Appearance", language: language)
        case .language: AppLocalization.string("Language", language: language)
        case .cullingAndMarking: AppLocalization.string("Culling & marking", language: language)
        case .browsingAndGroups: AppLocalization.string("Browsing & groups", language: language)
        case .photoDisplay: AppLocalization.string("Photo display", language: language)
        case .moveRejects: AppLocalization.string("Move rejects", language: language)
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .language: "globe"
        case .cullingAndMarking: "slider.horizontal.3"
        case .browsingAndGroups: "rectangle.stack"
        case .photoDisplay: "photo"
        case .moveRejects: "tray.and.arrow.down"
        }
    }

    var identifier: String {
        switch self {
        case .appearance: "clove.settings.category.appearance"
        case .language: "clove.settings.category.language"
        case .cullingAndMarking: "clove.settings.category.culling"
        case .browsingAndGroups: "clove.settings.category.browsing"
        case .photoDisplay: "clove.settings.category.photoDisplay"
        case .moveRejects: "clove.settings.category.moveRejects"
        }
    }
}

/// Nested detail pages under Culling & marking (issue #264).
enum SettingsSubpage: String, CaseIterable, Hashable, Identifiable, Sendable {
    case ratingScale
    case autoAdvanceDestination

    var id: String { rawValue }

    var title: String {
        title(language: .english)
    }

    func title(language: ResolvedAppLanguage) -> String {
        switch self {
        case .ratingScale: AppLocalization.string("Rating scale", language: language)
        case .autoAdvanceDestination: AppLocalization.string("After marking", language: language)
        }
    }

    var parentCategory: SettingsCategory {
        .cullingAndMarking
    }
}

/// Layout selection driven by available window width and size class rather than device identity.
enum SettingsLayoutMode: Equatable, Sendable {
    /// Minimum container width needed to present the category list beside its detail pane.
    static let wideWidthThreshold: CGFloat = 680

    static func isWide(horizontalSizeClass: UserInterfaceSizeClass?, availableWidth: CGFloat)
        -> Bool
    {
        horizontalSizeClass == .regular && availableWidth >= wideWidthThreshold
    }
}

/// Preserves the selected Settings category and nested depth when compact/wide layouts resize.
@MainActor
@Observable
final class SettingsNavigationState {
    var selectedCategory: SettingsCategory = .appearance
    var showsCompactDetail = false
    var activeSubpage: SettingsSubpage?

    func selectCategory(_ category: SettingsCategory, wide: Bool) {
        selectedCategory = category
        activeSubpage = nil
        showsCompactDetail = wide
    }

    func openCompactCategory(_ category: SettingsCategory) {
        selectedCategory = category
        showsCompactDetail = true
    }

    func openSubpage(_ subpage: SettingsSubpage) {
        selectedCategory = subpage.parentCategory
        showsCompactDetail = true
        activeSubpage = subpage
    }

    func enteredSettings(isWide: Bool) {
        if isWide {
            showsCompactDetail = true
        }
    }

    /// Updates compact-detail visibility when transitioning between wide and compact layouts so the
    /// active category stays on screen across resizes.
    func layoutChanged(isWide: Bool) {
        if isWide {
            // Wide split always presents a category on the right; keep compact aligned on shrink.
            showsCompactDetail = true
        }
    }

    func resetOnExit() {
        showsCompactDetail = false
        activeSubpage = nil
    }
}

/// Destinations pushed onto BrowseShell's single NavigationStack.
enum BrowseDestination: Hashable, Sendable {
    case detail
    case settings
    case settingsCategory(SettingsCategory)
    case settingsSubpage(SettingsSubpage)
}
