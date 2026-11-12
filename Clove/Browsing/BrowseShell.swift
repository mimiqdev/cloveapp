import CloveCore
import SwiftUI

/// One browsing state across widths: sidebar and grid at regular width, one screen at compact
/// width. Detail and Settings occupy the whole window, preserving the model's current filter.
struct BrowseShell: View {
    let browsing: BrowsingModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegular: Bool { horizontalSizeClass == .regular }

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
            .browsingChrome(title: title, browsing: browsing)
            .navigationDestination(for: BrowserRoute.self) { route in
                screen(for: route)
                    .browsingChrome(
                        title: title, browsing: browsing,
                        backTitle: isRegular && browsing.state.folder != nil
                            ? browsing.filterTitle : nil
                    )
                    .navigationBarBackButtonHidden()
            }
        }
        .overlay(alignment: .bottom) {
            if browsing.state.route == .detail, browsing.isSaveFailureToastVisible {
                Toast(
                    message: BrowsingModel.saveFailureToastMessage,
                    identifier: "clove.save.toast"
                )
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .task(id: browsing.saveFailureToastBurst) {
            guard browsing.isSaveFailureToastVisible else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            browsing.dismissSaveFailureToast()
        }
    }

    /// The existing route drives the stack, so resizing never creates another navigation state.
    private var navigationPath: Binding<[BrowserRoute]> {
        Binding(
            get: {
                switch browsing.state.route {
                case .detail, .settings: [browsing.state.route]
                case .entry, .grid: []
                }
            },
            set: { path in
                if path.isEmpty,
                    browsing.state.route == .detail || browsing.state.route == .settings
                {
                    browsing.back()
                }
            })
    }

    /// The outer stack pushes destinations over both columns and keeps the grid's viewport alive.
    private var folderLayout: some View {
        NavigationSplitView {
            FolderSidebar(browsing: browsing)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func screen(for route: BrowserRoute) -> some View {
        switch route {
        case .entry:
            EntryScreen(browsing: browsing)
        case .grid:
            GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
        case .detail:
            DetailScreen(browsing: browsing)
        case .settings:
            SettingsScreen()
        }
    }

    private var title: String {
        switch browsing.state.route {
        case .entry: "Clove"
        case .grid: "Photos"
        case .detail: browsing.currentPhoto?.fileName ?? "Photo"
        case .settings: "Settings"
        }
    }
}

extension View {
    /// Entry owns its header; regular-width Settings returns to the named grid filter.
    func browsingChrome(title: String, browsing: BrowsingModel, backTitle: String? = nil)
        -> some View
    {
        self
            .navigationTitle(
                browsing.state.route == .grid || browsing.state.route == .detail ? "" : title
            )
            .toolbar(
                browsing.state.route == .grid || browsing.state.route == .detail
                    ? .hidden : .visible,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if browsing.state.route == .settings, let backTitle {
                        Button {
                            browsing.back()
                        } label: {
                            Label(backTitle, systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("clove.nav.back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if browsing.state.route == .settings, backTitle == nil {
                        Button("Done") { browsing.back() }
                            .accessibilityIdentifier("clove.nav.back")
                    } else if browsing.state.route == .entry {
                        GlassIconButton(
                            label: "Settings", symbol: "gearshape", identifier: "clove.nav.settings"
                        ) {
                            browsing.showSettings()
                        }
                    }
                }
            }
    }
}
