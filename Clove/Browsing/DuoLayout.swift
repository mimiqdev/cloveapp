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
            .environment(\.usesVerticalBrowsingToolbar, edge != nil)
            .environment(\.hasFoldRegion, hasFoldRegion)
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
    @Entry var usesVerticalBrowsingToolbar = false
    @Entry var hasFoldRegion = false
    @Entry var isDuoExpanded = false
    @Entry var isDuoCover = false
}

/// The grid owns its filter/more/move controls; detail owns marking and preview state.
struct DuoDetailLayout {
    var presentation: Binding<DetailPresentation>
    var filter: AnyView
    var more: AnyView
    var bottom: AnyView
    var showsGrid: Bool
    /// The group whose expansion the person folded, shared with Photo Preview's grid so the
    /// Focus View filmstrip shows the same stack and folds back the same way (#225).
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

/// Shared Photo Preview 30/70 divider interaction for both `ArrangementView` and `SplitPhotoView`.
struct SplitDivider: View {
    @Binding var presentation: DetailPresentation
    let horizontal: Bool
    let contentExtent: CGFloat
    let back: () -> Void

    var body: some View {
        Divider()
            .contentShape(.interaction, Rectangle().inset(by: -22))
            .gesture(
                DragGesture(minimumDistance: 4).onEnded { value in
                    let next = presentation.released(
                        translation: horizontal
                            ? value.translation.width : value.translation.height,
                        contentWidth: contentExtent)
                    if next == .grid { back() } else { presentation = next }
                }
            )
            .accessibilityLabel("Photo split")
            .accessibilityValue("Grid 30 percent, photo 70 percent")
            .accessibilityAdjustableAction { direction in
                if direction == .decrement { presentation = .focus } else { back() }
            }
            .accessibilityIdentifier("clove.duo.divider")
    }
}

/// Horizontal 30/70 Photo Preview container for non-fold wide layouts across iOS versions. Keeping
/// `secondary` outside the conditional grid branch preserves its SwiftUI identity across toggles.
struct SplitPhotoView<Grid: View, Secondary: View>: View {
    let showsGrid: Bool
    @Binding var presentation: DetailPresentation
    let back: () -> Void
    @ViewBuilder let grid: () -> Grid
    @ViewBuilder let secondary: () -> Secondary

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let gridWidth =
                showsGrid
                ? (totalWidth * DetailPresentation.photoPreview.gridFraction).rounded() : 0
            HStack(spacing: 0) {
                if showsGrid {
                    HStack(spacing: 0) {
                        grid()
                        SplitDivider(
                            presentation: $presentation,
                            horizontal: true,
                            contentExtent: totalWidth,
                            back: back)
                    }
                    .frame(width: gridWidth)
                }
                secondary()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: totalWidth, height: proxy.size.height)
        }
    }
}

/// The arrangement owns pane geometry and adapts to reserved fold regions. Its API
/// has no drag-to-collapse navigation, so ``DetailPresentation`` retains the temporary snap/Back
/// transitions. The separator is the standard Divider, without custom chrome or sizing.
@available(iOS 27.1, *)
struct PhotoArrangement<Photo: View>: View {
    let grid: AnyView
    @Binding var presentation: DetailPresentation
    let back: () -> Void
    @ViewBuilder var photo: Photo

    var body: some View {
        ArrangementView {
            ArrangementGrid(grid: grid, presentation: $presentation, back: back)
                .splitArrangementLayoutRatio(
                    CGFloat(DetailPresentation.photoPreview.gridFraction))
        } secondary: {
            photo
        }
        .arrangementViewStyle(.split)
    }
}

@available(iOS 27.1, *)
private struct ArrangementGrid: View {
    let grid: AnyView
    @Binding var presentation: DetailPresentation
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
            SplitDivider(
                presentation: $presentation,
                horizontal: horizontal,
                contentExtent: primaryExtent
                    / CGFloat(DetailPresentation.photoPreview.gridFraction),
                back: back)
        }
        .onGeometryChange(for: CGFloat.self) {
            horizontal ? $0.size.width : $0.size.height
        } action: {
            primaryExtent = $0
        }
    }
}
