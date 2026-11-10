import SwiftUI

/// The 2 pt progress line under the toolbar (`design/handoff/components.md`, Progress line).
///
/// It fills in `accent` while the folder is read and in `group` while similar shots are found, and
/// it is hidden when the work is done, which `nil` progress does. The line reports reading and
/// grouping, never a mark, so VoiceOver skips it; the subtitle says the same thing in words
/// (copy.md `grid.subtitle.reading` and `.grouping`).
struct ProgressLine: View {
    /// How far the work has gone, 0 to 1, or nil when the line is hidden.
    var progress: Double?

    /// What the line is reporting, which picks its colour.
    var tone: Tone = .reading

    /// The identifier the screen's UI test uses.
    var identifier = "clove.progress"

    /// The two states components.md fills the line in.
    enum Tone {
        /// Reading the folder, in `accent`.
        case reading

        /// Finding similar shots, in `group`.
        case grouping

        /// The token the filled part uses.
        var colour: CloveColour {
            switch self {
            case .reading: Color.clove.accent
            case .grouping: Color.clove.group
            }
        }
    }

    @ViewBuilder
    var body: some View {
        if let progress {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.clove.separator)
                    Rectangle()
                        .fill(tone.colour)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 2)
            .accessibilityElement()
            .accessibilityIdentifier(identifier)
            .accessibilityHidden(true)
        }
    }
}

#Preview("Progress line") {
    VStack(spacing: 16) {
        ProgressLine(progress: 0.4, identifier: "preview.progress")
        ProgressLine(progress: 0.7, tone: .grouping, identifier: "preview.progress.grouping")
    }
    .padding(16)
    .background(Rectangle().fill(Color.clove.bg.canvas))
}
