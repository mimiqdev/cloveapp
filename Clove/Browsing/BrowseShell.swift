import CloveCore
import SwiftUI

/// One browsing state across widths: sidebar and grid at regular width, one screen at compact
/// width. Detail and Settings occupy the whole window, preserving the model's current filter.
struct BrowseShell: View {
    let browsing: BrowsingModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Environment(\.isDuoExpanded) private var isDuoExpanded
    @Environment(\.isDuoCover) private var isDuoCover
    @Environment(\.usesSystemBrowsingToolbar) private var usesSystemToolbar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language

    @State private var settingsNavigation = SettingsNavigationState()
    @State private var availableWidth: CGFloat = 0

    private var usesVerticalBar: Bool { isDuoExpanded || isDuoCover }

    private var isRegular: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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
                    } else {
                        GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                    }
                } else {
                    EntryScreen(browsing: browsing)
                }
            }
            .browsingChrome(
                title: title, browsing: browsing, usesSystemBar: usesSystemToolbar && !isRegular,
                language: language
            )
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
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                .toolbar(usesSystemToolbar ? .visible : .hidden, for: .navigationBar)
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
                .browsingChrome(
                    title: title, browsing: browsing, usesSystemBar: usesSystemToolbar,
                    language: language
                )
                .navigationBarBackButtonHidden()
        case .settings:
            SettingsScreen(
                navigation: settingsNavigation, availableWidth: availableWidth
            )
            .browsingChrome(
                title: title, browsing: browsing, usesSystemBar: usesSystemToolbar,
                backTitle: isRegular && browsing.state.folder != nil
                    ? AppLocalization.filterTitle(
                        for: browsing.state.filter, labelFilter: browsing.labelFilter,
                        language: language)
                    : nil,
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
    /// Entry owns its header; regular-width Settings returns to the named grid filter.
    func browsingChrome(
        title: String, browsing: BrowsingModel, usesSystemBar: Bool = false,
        backTitle: String? = nil, language: ResolvedAppLanguage = .english
    )
        -> some View
    {
        self
            .navigationTitle(
                browsing.state.route == .grid
                    || browsing.state.route == .detail
                    || browsing.state.route == .entry ? "" : title
            )
            .toolbar(
                !usesSystemBar
                    && (browsing.state.route == .grid || browsing.state.route == .detail
                        || browsing.state.route == .entry)
                    ? .hidden : .visible,
                for: .navigationBar
            )
            .toolbar {
                if browsing.state.route == .settings, let backTitle {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            browsing.back()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text(backTitle)
                            }
                        }
                        .accessibilityLabel(AppLocalization.string("Back", language: language))
                        .accessibilityIdentifier("clove.nav.back")
                    }
                } else if browsing.state.route == .settings {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalization.string("Done", language: language)) {
                            browsing.back()
                        }
                        .accessibilityIdentifier("clove.nav.back")
                    }
                }
                // Entry owns its header (screens.md §01): its own large title and gear,
                // so no toolbar item is added there.
            }
    }
}
