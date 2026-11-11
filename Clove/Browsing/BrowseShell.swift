import CloveCore
import SwiftUI

/// The browsing shell: one browsing state, drawn by whichever layout the available width allows
/// (PRD P0-13, P0-14, G1 fold-state row).
///
/// Compact width shows one screen at a time behind a back button; regular width shows the grid
/// beside the detail or the group view. Both read the same ``BrowsingModel``, so a fold, an
/// unfold or a resize changes only which layout draws the state (G1 fold-state row). The choice
/// reads the width class the view is handed, never a device name or model. The leaving question
/// belongs to the shell because entry, the grid, the group view and settings can all be left.
struct BrowseShell: View {
    /// The scene's browsing state and the operations the screens perform on it.
    let browsing: BrowsingModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if usesSplitLayout {
                splitLayout
            } else {
                compactLayout
            }
        }
        // PRD Failure and recovery asks before leaving a folder with unconfirmed writes, wherever
        // the leaving started: the back button, a pick or a Recents tap.
        .modifier(LeaveFolderPromptView(browsing: browsing))
    }

    /// Compact width: one screen at a time (PRD single-screen iPhone).
    private var compactLayout: some View {
        NavigationStack {
            screen(for: browsing.state.route)
                .browsingChrome(title: title, browsing: browsing)
        }
    }

    /// Regular width: the grid with the detail or the group view (PRD iPad and Duo inner screen).
    ///
    /// Entry and settings keep one column, because they have no second pane to fill.
    private var splitLayout: some View {
        NavigationStack {
            Group {
                if browsing.state.route == .entry || browsing.state.route == .settings {
                    screen(for: browsing.state.route)
                } else {
                    HStack(spacing: 0) {
                        GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
                            .frame(minWidth: 320, idealWidth: 420, maxWidth: 560)
                        Divider()
                        detailColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .browsingChrome(title: title, browsing: browsing)
        }
    }

    /// The wide layout's second pane: the detail, the group view, or what a tap opens.
    @ViewBuilder
    private var detailColumn: some View {
        switch browsing.state.route {
        case .detail:
            DetailScreen(browsing: browsing)
        case .group:
            GroupScreen(browsing: browsing)
        default:
            ContentUnavailableView(
                "No photo", systemImage: "photo", description: Text("Choose a photo in the grid."))
        }
    }

    /// One screen for a route (PRD P0-13).
    @ViewBuilder
    private func screen(for route: BrowserRoute) -> some View {
        switch route {
        case .entry:
            EntryScreen(browsing: browsing)
        case .grid:
            GridScreen(browsing: browsing, thumbnails: browsing.thumbnails)
        case .detail:
            DetailScreen(browsing: browsing)
        case .group:
            GroupScreen(browsing: browsing)
        case .settings:
            SettingsScreen()
        }
    }

    /// The title the route's screen shows.
    private var title: String {
        switch browsing.state.route {
        case .entry:
            "Clove"
        case .grid:
            "Photos"
        case .detail:
            browsing.currentPhoto?.fileName ?? "Photo"
        case .group:
            "Group"
        case .settings:
            "Settings"
        }
    }

    /// Whether the available width fits the grid beside the detail (G1 fold-state row).
    ///
    /// A half-folded or narrow window is compact and a wide one splits. P3 adds the half-folded
    /// Duo's hinge avoidance on top of this decision, without moving any state out of the model.
    private var usesSplitLayout: Bool { horizontalSizeClass == .regular }
}

extension View {
    /// Shared navigation for browsing, with Entry's own header and Settings' Done action
    /// (PRD P0-13; handoff Entry and Settings).
    func browsingChrome(title: String, browsing: BrowsingModel) -> some View {
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
                if browsing.state.route == .group {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") { browsing.back() }
                            .accessibilityIdentifier("clove.nav.back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if browsing.state.route == .settings {
                        Button("Done") { browsing.back() }
                            .accessibilityIdentifier("clove.nav.back")
                    } else if browsing.state.route == .entry {
                        GlassIconButton(
                            label: "Settings", symbol: "gearshape", identifier: "clove.nav.settings"
                        ) {
                            browsing.showSettings()
                        }
                    } else if browsing.state.route == .group {
                        Button("Settings", systemImage: "gearshape") { browsing.showSettings() }
                            .accessibilityIdentifier("clove.nav.settings")
                    }
                }
            }
    }
}
