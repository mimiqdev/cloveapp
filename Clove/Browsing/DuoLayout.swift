import CloveCore
import SwiftUI

/// The system identifies the vertical bar and the inner display's reserved fold region.
/// Size classes select a presentation only after those system signals identify the context.
struct DuoLayout: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(SystemBrowsingLayout())
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct SystemBrowsingLayout: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var hasFoldRegion = false

    func body(content: Content) -> some View {
        content
            .environment(\.usesSystemBrowsingToolbar, true)
            .environment(\.isDuoExpanded, (edge != nil || hasFoldRegion) && sizeClass == .regular)
            .environment(\.isDuoCover, edge != nil && sizeClass != .regular)
            .onGeometryChange(for: Bool.self) {
                !$0.reservedRegions(kind: .division, options: .includeInactive).isEmpty
            } action: {
                hasFoldRegion = $0
            }
    }
}

extension EnvironmentValues {
    @Entry var usesSystemBrowsingToolbar = false
    @Entry var isDuoExpanded = false
    @Entry var isDuoCover = false
}

/// The grid owns its tools and sheets; the detail owns marking and preview state.
struct DuoDetailLayout {
    var split: Binding<DuoSplit>
    var grid: AnyView
    var filter: AnyView
    var more: AnyView
    var bottom: AnyView
    var showsGrid: Bool
    /// The group whose expansion the person folded, shared with the split's grid, so the
    /// photo-only strip shows the same stack and folds back the same way (#225).
    var foldedGroup: Binding<GroupID?>?
}

/// One set of semantic toolbar groups for both axes. The navigation container owns
/// placement, chrome, spacing, overflow, and safe areas, including the cover's camera.
@available(iOS 27.1, *)
struct BrowsingToolbar<NavigationTools: View, Tools: View, Marks: ToolbarContent, Bottom: View>:
    ToolbarContent
{
    let back: () -> Void
    let undo: () -> Void
    let canUndo: Bool
    var showsBack = true
    var showsUndo = true
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @ViewBuilder var navigationTools: NavigationTools
    @ViewBuilder var tools: Tools
    @ToolbarContentBuilder var marks: Marks
    @ViewBuilder var bottom: Bottom

    init(
        back: @escaping () -> Void,
        undo: @escaping () -> Void,
        canUndo: Bool,
        showsBack: Bool = true,
        showsUndo: Bool = true,
        @ViewBuilder navigationTools: () -> NavigationTools = { EmptyView() },
        @ViewBuilder tools: () -> Tools,
        @ToolbarContentBuilder marks: () -> Marks,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.back = back
        self.undo = undo
        self.canUndo = canUndo
        self.showsBack = showsBack
        self.showsUndo = showsUndo
        self.navigationTools = navigationTools()
        self.tools = tools()
        self.marks = marks()
        self.bottom = bottom()
    }

    var body: some ToolbarContent {
        if usesVerticalBar {
            if showsBack {
                ToolbarItem(placement: .cancellationAction) {
                    backButton
                }
                .axisBehavior(.verticalPreferred)
            }
        } else if showsBack || NavigationTools.self != EmptyView.self {
            ToolbarItemGroup(placement: .topBarLeading) {
                if showsBack { backButton }
                navigationTools
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            tools
        }
        .axisBehavior(.verticalPreferred)
        marks
        if usesVerticalBar {
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                if showsUndo { undoButton }
                bottom
            }
            .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsUndo { undoButton }
                bottom
            }
        }
    }

    private var usesVerticalBar: Bool { verticalEdge != nil }

    private var backButton: some View {
        Button("Back", systemImage: "chevron.left", action: back)
            .accessibilityIdentifier("clove.nav.back")
    }

    private var undoButton: some View {
        Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
            .disabled(!canUndo)
            .accessibilityIdentifier(usesVerticalBar ? "clove.duo.undo" : "clove.detail.undo")
    }
}

/// The arrangement owns pane geometry and adapts to reserved fold regions. Its API
/// has no drag-to-collapse navigation, so DuoSplit retains the temporary snap/Back
/// transitions. The separator is the standard Divider, without custom chrome or sizing.
@available(iOS 27.1, *)
struct PhotoArrangement<Photo: View>: View {
    let grid: AnyView
    @Binding var split: DuoSplit
    let back: () -> Void
    @ViewBuilder var photo: Photo

    var body: some View {
        ArrangementView {
            ArrangementGrid(grid: grid, split: $split, back: back)
                .splitArrangementLayoutRatio(CGFloat(DuoSplit.focus.gridFraction))
        } secondary: {
            photo
        }
        .arrangementViewStyle(.split)
    }
}

@available(iOS 27.1, *)
private struct ArrangementGrid: View {
    let grid: AnyView
    @Binding var split: DuoSplit
    let back: () -> Void
    @Environment(\.splitArrangementAxis) private var axis
    @State private var primaryExtent: CGFloat = 0

    var body: some View {
        let horizontal = axis == .horizontal
        let layout =
            horizontal
            ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            grid
            Divider()
                .contentShape(.interaction, Rectangle().inset(by: -22))
                .gesture(
                    DragGesture(minimumDistance: 4).onEnded { value in
                        let next = split.released(
                            translation: horizontal
                                ? value.translation.width : value.translation.height,
                            contentWidth: primaryExtent / CGFloat(DuoSplit.focus.gridFraction))
                        if next == .grid { back() } else { split = next }
                    }
                )
                .accessibilityLabel("Photo split")
                .accessibilityValue("Grid 30 percent, photo 70 percent")
                .accessibilityAdjustableAction { direction in
                    if direction == .decrement { split = .photoOnly } else { back() }
                }
                .accessibilityIdentifier("clove.duo.divider")
        }
        .onGeometryChange(for: CGFloat.self) {
            horizontal ? $0.size.width : $0.size.height
        } action: {
            primaryExtent = $0
        }
    }
}
