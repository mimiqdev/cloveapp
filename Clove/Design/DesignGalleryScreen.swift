import CloveCore
import SwiftUI

/// Whether this launch shows the design gallery instead of the app
/// (`design/handoff/README.md`, suggested build order).
///
/// The gallery exists for previews, screenshots and the UI test, never for normal use: nothing in
/// the app's navigation reaches it, and it appears only when the launch environment asks for it.
enum DesignGalleryLaunch {
    /// The launch environment value that shows the gallery: set it to `1`.
    static let variable = "CLOVE_DESIGN_GALLERY"

    /// Whether this launch shows the gallery.
    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[variable] == "1"
    }
}

/// Every shared control in every state, with a theme switcher, for previews and screenshots
/// (`design/handoff/components.md`, `README.md` build order steps 1 and 2).
///
/// The gallery keeps V1 checkable before V2–V4 wire the controls into the screens: it draws each
/// control with plain sample values and empty closures, and switching a theme shows all of them in
/// that theme at once.
struct DesignGalleryScreen: View {
    /// The theme the gallery draws, changed by the switcher at the top.
    @State private var theme = CloveTheme.light

    /// Sample ratings and labels for the states below.
    private let threeStars = (Rating(rawValue: 3) ?? .unrated)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    themeSwitcher
                    glassButtons
                    moveRejects
                    markCapsule
                    marks
                    starBar
                    labelPicker
                    toast
                    banner
                    pillActions
                    progress
                    themeTiles
                }
                .padding(16)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Rectangle().fill(Color.clove.bg.canvas).ignoresSafeArea())
            .navigationTitle("Design gallery")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.cloveTheme, theme)
        .preferredColorScheme(theme.appearance.colorScheme)
        .accessibilityIdentifier("clove.design.gallery")
    }

    /// The theme switcher, so a screenshot can show the same controls in another theme.
    private var themeSwitcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(CloveTheme.allCases) { candidate in
                    Button {
                        theme = candidate
                    } label: {
                        Text(candidate.name)
                            .font(.footnote.weight(candidate == theme ? .semibold : .regular))
                            .foregroundStyle(
                                candidate == theme ? Color.clove.accent : Color.clove.text.secondary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                if candidate == theme {
                                    Capsule().fill(Color.clove.surface.card)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(candidate == theme ? .isSelected : [])
                    .accessibilityIdentifier("clove.design.gallery.theme.\(candidate.id)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// The glass icon button in its normal and filter-active states (components.md).
    private var glassButtons: some View {
        section("Glass icon buttons") {
            HStack(spacing: 12) {
                GlassIconButton(
                    label: "Info", symbol: "info.circle",
                    identifier: "clove.design.gallery.button.info", action: {})
                GlassIconButton(
                    label: "Filter", symbol: "line.3.horizontal.decrease", isActive: true,
                    identifier: "clove.design.gallery.button.filterActive", action: {})
                GlassIconButton(
                    label: "More", symbol: "ellipsis", size: .pad,
                    identifier: "clove.design.gallery.button.pad", action: {})
                GlassIconButton(
                    label: "Undo", symbol: "arrow.uturn.backward", size: .duo,
                    identifier: "clove.design.gallery.button.duo", action: {})
            }
        }
    }

    /// The Move Rejects button (components.md).
    private var moveRejects: some View {
        section("Move rejects") {
            MoveRejectsButton(identifier: "clove.design.gallery.moveRejects", action: {})
        }
    }

    /// The mark capsule with no marks, with marks and with Reject on (components.md).
    private var markCapsule: some View {
        section("Mark capsule") {
            VStack(spacing: 12) {
                MarkCapsule(
                    rating: .unrated, label: nil, isRejected: false,
                    identifier: "clove.design.gallery.capsule.unmarked",
                    onRate: noRate, onReject: {}, onLabel: {})
                MarkCapsule(
                    rating: threeStars, label: .blue, isRejected: false,
                    identifier: "clove.mark.capsule", onRate: noRate, onReject: {}, onLabel: {})
                MarkCapsule(
                    rating: threeStars, label: .red, isRejected: true,
                    identifier: "clove.design.gallery.capsule.rejected",
                    onRate: noRate, onReject: {}, onLabel: {})
            }
        }
    }

    /// The Reject circle, the stars and the label circle on their own (components.md).
    private var marks: some View {
        section("Reject, stars and label") {
            HStack(spacing: 16) {
                RejectCircle(
                    isRejected: false, identifier: "clove.design.gallery.reject.off", onToggle: {})
                RejectCircle(
                    isRejected: true, identifier: "clove.design.gallery.reject.on", onToggle: {})
                StarRow(
                    rating: threeStars, identifier: "clove.design.gallery.stars", onRate: noRate)
                LabelCircle(label: nil, identifier: "clove.design.gallery.label.none", onTap: {})
                LabelCircle(
                    label: .green, identifier: "clove.design.gallery.label.green", onTap: {})
            }
        }
    }

    /// The vertical star bar at the iPhone and iPad sizes (components.md).
    private var starBar: some View {
        section("Vertical star bar") {
            HStack(alignment: .top, spacing: 16) {
                VerticalStarBar(
                    rating: threeStars, identifier: "clove.mark.starBar", onRate: noRate,
                    onReject: {})
                VerticalStarBar(
                    rating: threeStars, size: .pad, showsRejectChip: false,
                    identifier: "clove.design.gallery.starBar.pad", onRate: noRate, onReject: {})
            }
        }
    }

    /// The label picker with the five default labels and with the extended ones (components.md).
    private var labelPicker: some View {
        section("Label picker") {
            VStack(alignment: .leading, spacing: 12) {
                LabelPicker(
                    selection: .green, identifier: "clove.mark.labelPicker", onPick: { _ in })
                LabelPicker(
                    selection: .orange, labels: [nil] + LabelColour.allCases,
                    identifier: "clove.design.gallery.labelPicker.extended", onPick: { _ in })
            }
        }
    }

    /// The toast with an Undo action and with a second line and Details (components.md).
    private var toast: some View {
        section("Toast") {
            VStack(spacing: 12) {
                Toast(
                    message: "Moved 42 to _Rejected", actionTitle: "Undo",
                    identifier: "clove.toast", onAction: {})
                Toast(
                    message: "Moved 40 to _Rejected", detail: "2 couldn't be moved",
                    actionTitle: "Details",
                    identifier: "clove.design.gallery.toast.details", onAction: {})
            }
        }
    }

    /// The error banner (components.md).
    private var banner: some View {
        section("Error banner") {
            ErrorBanner(
                message: "The drive disconnected.",
                detail: "Reconnect it, then reopen this folder.", actionTitle: "Reopen",
                identifier: "clove.banner", action: {})
        }
    }

    /// The pill action in both tones (components.md).
    private var pillActions: some View {
        section("Pill action") {
            HStack(spacing: 12) {
                PillAction(
                    title: "Reject 6 unmarked", tone: .reject,
                    identifier: "clove.design.gallery.pill.reject", action: {})
                PillAction(
                    title: "Continue →", tone: .accent, identifier: "clove.pillAction", action: {})
            }
        }
    }

    /// The progress line while reading and while grouping (components.md).
    private var progress: some View {
        section("Progress line") {
            VStack(spacing: 12) {
                ProgressLine(progress: 0.4, identifier: "clove.progress")
                ProgressLine(
                    progress: 0.7, tone: .grouping,
                    identifier: "clove.design.gallery.progress.grouping")
            }
        }
    }

    /// The theme tile, selected and not (components.md, Theme tile).
    private var themeTiles: some View {
        section("Theme tiles") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(CloveTheme.allCases) { candidate in
                        ThemeTile(theme: candidate, isSelected: candidate == theme)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// One labelled block of the gallery.
    private func section(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.clove.text.secondary)
            content()
        }
        .accessibilityElement(children: .contain)
    }

    /// The gallery draws state, it does not apply marks.
    private func noRate(_ rating: Rating) {}
}
