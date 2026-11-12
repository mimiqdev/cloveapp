import CloveCore
import SwiftUI

/// The marking key a hardware key press makes on the detail view (PRD Gestures and keyboard).
///
/// This is the app's only translation from a hardware key to ``MarkingKey``. The detail view
/// hands the result to the same marking path as the rail, the capsule and the swipe, so the
/// keyboard carries no marking rules of its own (PRD P0-06).
///
/// Command, Control and Option belong to the system, except `⌘Z`, which undoes (PRD keyboard
/// table). Shift and the keypad's own flags are ignored, so `X` rejects like `x` and a keypad `3`
/// rates like the row above the letters.
extension MarkingKey {
    /// The key for one press, or nil when the detail view leaves the press alone.
    init?(_ press: KeyPress) {
        guard press.modifiers.isDisjoint(with: [.control, .option]) else { return nil }
        if press.modifiers.contains(.command) {
            guard !press.modifiers.contains(.shift), press.key == "z" else { return nil }
            self = .undo
            return
        }
        switch press.key {
        case .upArrow:
            self = .nextRating
            return
        case .downArrow:
            self = .reject
            return
        case .leftArrow:
            self = .previousPhoto
            return
        case .rightArrow:
            self = .nextPhoto
            return
        default:
            break
        }
        switch press.characters.lowercased() {
        case "0", "1", "2", "3", "4", "5":
            guard let level = Int(press.characters).flatMap(Rating.init(rawValue:)) else {
                return nil
            }
            self = .rating(level)
        case "6":
            self = .colourLabel(.red)
        case "7":
            self = .colourLabel(.yellow)
        case "8":
            self = .colourLabel(.green)
        case "9":
            self = .colourLabel(.blue)
        case "x":
            self = .reject
        default:
            return nil
        }
    }
}
