import CloveCore
import SwiftUI

/// One browsing state across widths: sidebar and grid at regular width, one screen at compact
/// width. Detail and Settings occupy the whole window, preserving the model's current filter.
struct BrowseShell: View {
    static let idealSidebarWidth: CGFloat = 280

    let browsing: BrowsingModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Environment(\.cloveUserInterfaceIdiom) private var overrideUserInterfaceIdiom
    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language

    @State private var settingsNavigation = SettingsNavigationState()
    @State private var availableWidth: CGFloat = 0

    private var userInterfaceIdiom: UIUserInterfaceIdiom {
        overrideUserInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
    }
    private var usesVerticalBar: Bool { isDuoExpanded || isDuoCover }

    private var isRegular: Bool {
        userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular
            && !isDuoExpanded
    }

    private var isWideSettings: Bool {
        SettingsLayoutMode.isWide(
            horizontalSizeClass: horizontalSizeClass, availableWidth: availableWidth)
    }

    var body: some View {
        NavigationStack(path: navigationPath) {
            Group {
                if browsing.state.route != .entry, browsing.state.folder != nil {
                    if isRegular {
                        folderLayout
                            .toolbarVisibility(.hidden, for: .navigationBar)
                    } else {
                        GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                    }
                } else {
                    EntryScreen(browsing: browsing)
                }
            }
            .navigationTitle("")
            .navigationDestination(for: BrowseDestination.self) { destination in
                screen(for: destination)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
        .onChange(of: browsing.state.route) { _, route in
            if route != .settings {
                settingsNavigation.resetOnExit()
            }
        }
        .task(id: browsing.failureToastBurst) {
            guard browsing.failureToastMessage != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(CloveMotion.chrome(reduceMotion: reduceMotion)) {
                browsing.dismissFailureToast()
            }
        }
    }

    /// The existing route drives the stack, so resizing never creates another navigation state.
    private var navigationPath: Binding<[BrowseDestination]> {
        Binding(
            get: {
                switch browsing.state.route {
                case .detail:
                    return usesVerticalBar ? [] : [.detail]
                case .settings:
                    var path: [BrowseDestination] = [.settings]
                    if !isWideSettings, settingsNavigation.showsCompactDetail {
                        path.append(.settingsCategory(settingsNavigation.selectedCategory))
                    }
                    if let subpage = settingsNavigation.activeSubpage {
                        path.append(.settingsSubpage(subpage))
                    }
                    return path
                case .entry, .grid:
                    return []
                }
            },
            set: { path in
                if path.isEmpty {
                    if browsing.state.route == .detail || browsing.state.route == .settings {
                        settingsNavigation.resetOnExit()
                        browsing.back()
                    }
                    return
                }
                guard browsing.state.route == .settings else { return }
                syncSettingsPath(path)
            })
    }

    private func syncSettingsPath(_ path: [BrowseDestination]) {
        if case .settingsSubpage(let subpage) = path.last {
            settingsNavigation.openSubpage(subpage)
            return
        }
        settingsNavigation.activeSubpage = nil
        if case .settingsCategory(let category) = path.last {
            settingsNavigation.openCompactCategory(category)
            return
        }
        if path == [.settings], !isWideSettings {
            settingsNavigation.showsCompactDetail = false
        }
    }

    /// The outer stack pushes destinations over both columns and keeps the grid's viewport alive.
    private var folderLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            FolderSidebar(browsing: browsing)
                .navigationSplitViewColumnWidth(
                    min: 220, ideal: Self.idealSidebarWidth, max: 300
                )
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                .toolbar(.visible, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(
            \.folderPreparationPresentationMode,
            FolderPreparationPresentationMode.resolved(horizontalSizeClass: horizontalSizeClass))
    }

    @ViewBuilder
    private func screen(for destination: BrowseDestination) -> some View {
        switch destination {
        case .detail:
            DetailScreen(browsing: browsing)
                .navigationTitle("")
                .navigationBarBackButtonHidden()
        case .settings:
            SettingsScreen(
                navigation: settingsNavigation, availableWidth: availableWidth
            ) {
                browsing.back()
            }
            .browsingChrome(
                title: title, browsing: browsing,
                hidesSettingsBar: isWideSettings,
                language: language
            )
            .navigationBarBackButtonHidden()
        case .settingsCategory(let category):
            SettingsCategoryScreen(category: category)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalization.string("Done", language: language)) {
                            browsing.back()
                        }
                        .accessibilityIdentifier("clove.nav.back")
                    }
                }
                .toolbarVisibility(.visible, for: .navigationBar)
        case .settingsSubpage(let subpage):
            SettingsSubpageScreen(subpage: subpage)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalization.string("Done", language: language)) {
                            browsing.back()
                        }
                        .accessibilityIdentifier("clove.nav.back")
                    }
                }
                .toolbarVisibility(.visible, for: .navigationBar)
        }
    }

    private var title: String {
        switch browsing.state.route {
        case .entry: "Clove"
        case .grid: AppLocalization.string("Photos", language: language)
        case .detail:
            browsing.currentPhoto?.fileName ?? AppLocalization.string("Photo", language: language)
        case .settings: AppLocalization.string("Settings", language: language)
        }
    }
}

extension View {
    /// Applies navigation title, compact Done action, and bar visibility for Settings.
    func browsingChrome(
        title: String, browsing: BrowsingModel,
        hidesSettingsBar: Bool = false, language: ResolvedAppLanguage = .english
    )
        -> some View
    {
        modifier(
            BrowsingChromeModifier(
                title: title, browsing: browsing,
                hidesSettingsBar: hidesSettingsBar, language: language))
    }
}

private struct BrowsingChromeModifier: ViewModifier {
    let title: String
    let browsing: BrowsingModel
    let hidesSettingsBar: Bool
    let language: ResolvedAppLanguage

    private var barVisibility: Visibility {
        (browsing.state.route == .settings && hidesSettingsBar) ? .hidden : .visible
    }

    func body(content: Content) -> some View {
        content
            .navigationTitle(
                browsing.state.route == .grid
                    || browsing.state.route == .detail
                    || browsing.state.route == .entry ? "" : title
            )
            .toolbar {
                if browsing.state.route == .settings, !hidesSettingsBar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalization.string("Done", language: language)) {
                            browsing.back()
                        }
                        .accessibilityIdentifier("clove.nav.back")
                    }
                }
            }
            .toolbarVisibility(barVisibility, for: .navigationBar)
    }
}
