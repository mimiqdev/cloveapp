import SwiftUI

/// The handoff's group count badge, shared by every grid and filmstrip stack (components.md).
///
/// The chip is a photo overlay, not a theme colour: a black scrim with a near-white number reads
/// the same on a bright or a dark photo in every theme (owner decision, 2026-11-13, #226). It
/// never uses `group` or another accent, so a count stops looking like a notification.
struct GroupCountBadge: View {
    /// Where the badge sits, which changes only its type size and corner radius (components.md).
    enum Presentation {
        /// A grid cell's stack: 11 pt in a 4 pt rounded rectangle.
        case grid

        /// A filmstrip stack: 9 pt in a 3 pt rounded rectangle, so it stays quiet at 54 × 60.
        case filmstrip

        var pointSize: CGFloat {
            switch self {
            case .grid: 11
            case .filmstrip: 9
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .grid: 4
            case .filmstrip: 3
            }
        }
    }

    let count: Int
    let presentation: Presentation

    var body: some View {
        Text(count.formatted())
            .font(.system(size: presentation.pointSize, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.94))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            // The scrim is on the shape alone, so the count keeps its contrast without a border.
            .background(
                Color.black.opacity(0.56),
                in: RoundedRectangle(cornerRadius: presentation.cornerRadius))
    }
}
