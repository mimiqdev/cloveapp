import CloveCore
import SwiftUI
import UIKit

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
    @Entry var cloveUserInterfaceIdiom: UIUserInterfaceIdiom? = nil
    @Entry var usesSystemBrowsingToolbar = false
    @Entry var usesVerticalBrowsingToolbar = false
    @Entry var hasFoldRegion = false
    @Entry var isDuoExpanded = false
    @Entry var isDuoCover = false
}

struct DuoDetailLayout {
    var presentation: Binding<DetailPresentation>
    var filter: AnyView
    var more: AnyView
    var bottom: AnyView
    var showsGrid: Bool
}

/// One set of semantic toolbar groups for both axes. The navigation container owns
/// placement, chrome, spacing, overflow, and safe areas, including the cover's camera.
@available(iOS 27.1, *)
struct BrowsingToolbar<
    NavigationTools: View,
    HorizontalLeadingTools: View,
    StandaloneDockTool: View,
    HorizontalTools: View,
    Tools: View,
    Marks: ToolbarContent,
    Bottom: View
>: ToolbarContent {
    let back: () -> Void
    let undo: () -> Void
    let canUndo: Bool
    var showsBack = true
    var showsUndo = true
    var backTitle: String? = nil
    var showsNavigationTools = true
    var showsHorizontalLeadingTools = false
    var showsStandaloneDockTool = false
    var showsHorizontalTools = false
    var showsTools = true
    var showsBottom = true
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @Environment(\.appLanguage) private var language
    @ViewBuilder var navigationTools: NavigationTools
    @ViewBuilder var horizontalLeadingTools: HorizontalLeadingTools
    @ViewBuilder var standaloneDockTool: StandaloneDockTool
    @ViewBuilder var horizontalTools: HorizontalTools
    @ViewBuilder var tools: Tools
    @ToolbarContentBuilder var marks: Marks
    @ViewBuilder var bottom: Bottom

    init(
        back: @escaping () -> Void,
        undo: @escaping () -> Void,
        canUndo: Bool,
        showsBack: Bool = true,
        showsUndo: Bool = true,
        backTitle: String? = nil,
        showsNavigationTools: Bool = NavigationTools.self != EmptyView.self,
        showsHorizontalLeadingTools: Bool = HorizontalLeadingTools.self != EmptyView.self,
        showsStandaloneDockTool: Bool = StandaloneDockTool.self != EmptyView.self,
        showsHorizontalTools: Bool = HorizontalTools.self != EmptyView.self,
        showsTools: Bool = true,
        showsBottom: Bool = Bottom.self != EmptyView.self,
        @ViewBuilder navigationTools: () -> NavigationTools = { EmptyView() },
        @ViewBuilder horizontalLeadingTools: () -> HorizontalLeadingTools = { EmptyView() },
        @ViewBuilder standaloneDockTool: () -> StandaloneDockTool = { EmptyView() },
        @ViewBuilder horizontalTools: () -> HorizontalTools = { EmptyView() },
        @ViewBuilder tools: () -> Tools,
        @ToolbarContentBuilder marks: () -> Marks,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.back = back
        self.undo = undo
        self.canUndo = canUndo
        self.showsBack = showsBack
        self.showsUndo = showsUndo
        self.backTitle = backTitle
        self.showsNavigationTools = showsNavigationTools
        self.showsHorizontalLeadingTools = showsHorizontalLeadingTools
        self.showsStandaloneDockTool = showsStandaloneDockTool
        self.showsHorizontalTools = showsHorizontalTools
        self.showsTools = showsTools
        self.showsBottom = showsBottom
        self.navigationTools = navigationTools()
        self.horizontalLeadingTools = horizontalLeadingTools()
        self.standaloneDockTool = standaloneDockTool()
        self.horizontalTools = horizontalTools()
        self.tools = tools()
        self.marks = marks()
        self.bottom = bottom()
    }

    var body: some ToolbarContent {
        if usesVerticalBar {
            if showsHorizontalLeadingTools {
                ToolbarItemGroup(placement: .topBarLeading) {
                    horizontalLeadingTools
                }
                .axisBehavior(.horizontalOnly)
            }
            if showsBack {
                ToolbarItem(placement: .cancellationAction) {
                    backButton
                }
                .axisBehavior(.verticalPreferred)
            }
            if showsStandaloneDockTool {
                ToolbarItem(placement: .topBarTrailing) {
                    standaloneDockTool
                }
                .axisBehavior(.verticalPreferred)
                if showsTools {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
            }
        } else if showsBack || showsStandaloneDockTool || showsNavigationTools {
            ToolbarItemGroup(placement: .topBarLeading) {
                if showsBack { backButton }
                if showsStandaloneDockTool { standaloneDockTool }
                if showsNavigationTools { navigationTools }
            }
        }
        if showsHorizontalTools {
            ToolbarItemGroup(placement: .topBarTrailing) {
                horizontalTools
            }
            .axisBehavior(.horizontalOnly)
        }
        if showsTools {
            ToolbarItemGroup(placement: .topBarTrailing) {
                tools
            }
            .axisBehavior(.verticalPreferred)
        }
        marks
        if usesVerticalBar {
            if showsUndo || showsBottom {
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    if showsUndo { undoButton }
                    if showsBottom { bottom }
                }
                .axisBehavior(.verticalPreferred)
            }
        } else if showsUndo || showsBottom {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsUndo { undoButton }
                if showsBottom { bottom }
            }
        }
    }

    private var usesVerticalBar: Bool { verticalEdge != nil }

    @ViewBuilder
    private var backButton: some View {
        if !usesVerticalBar, let backTitle, !backTitle.isEmpty {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(backTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 160, alignment: .leading)
            }
            .accessibilityLabel(AppLocalization.string("Back", language: language))
            .accessibilityIdentifier("clove.nav.back")
        } else {
            Button(
                AppLocalization.string("Back", language: language), systemImage: "chevron.left",
                action: back
            )
            .accessibilityIdentifier("clove.nav.back")
        }
    }

    private var undoButton: some View {
        Button(
            AppLocalization.string("Undo", language: language), systemImage: "arrow.uturn.backward",
            action: undo
        )
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
    @Environment(\.appLanguage) private var language

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
            .accessibilityLabel(AppLocalization.string("Photo split", language: language))
            .accessibilityValue(
                AppLocalization.string("Grid 30 percent, photo 70 percent", language: language)
            )
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
