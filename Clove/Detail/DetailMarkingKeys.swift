import CloveCore
import SwiftUI
import UIKit

/// The marking key a hardware key press makes on the detail view (PRD Gestures and keyboard).
///
/// This is the app's only translation from a hardware key to ``MarkingKey``. The detail view
/// hands the result to the same marking path as the capsule and the swipe, so the keyboard
/// carries no marking rules of its own (PRD P0-06).
///
/// Command, Control and Option belong to the system, except `⌘Z`, which undoes (PRD keyboard
/// table). Shift and the keypad's own flags are ignored, so `X` rejects like `x` and a keypad `3`
/// rates like the row above the letters.
extension MarkingKey {
    private enum HardwareSpecialKey {
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case enter
        case escape
    }

    /// The key for one SwiftUI press, or nil when the detail view leaves the press alone.
    init?(_ press: KeyPress) {
        let specialKey: HardwareSpecialKey? =
            switch press.key {
            case .upArrow: .upArrow
            case .downArrow: .downArrow
            case .leftArrow: .leftArrow
            case .rightArrow: .rightArrow
            case .return: .enter
            case .escape: .escape
            default: nil
            }
        self.init(
            specialKey: specialKey,
            characters: press.characters,
            hasControlOrOption: !press.modifiers.isDisjoint(with: [.control, .option]),
            hasCommand: press.modifiers.contains(.command),
            hasShift: press.modifiers.contains(.shift),
            isUndoLetter: press.key == "z")
    }

    /// The key for one UIKit hardware press, or nil when the detail view leaves the press alone.
    init?(_ key: UIKey) {
        let specialKey: HardwareSpecialKey? =
            switch key.keyCode {
            case .keyboardUpArrow: .upArrow
            case .keyboardDownArrow: .downArrow
            case .keyboardLeftArrow: .leftArrow
            case .keyboardRightArrow: .rightArrow
            case .keyboardReturnOrEnter, .keyboardReturn: .enter
            case .keyboardEscape: .escape
            default: nil
            }
        let characters = key.characters.isEmpty ? key.charactersIgnoringModifiers : key.characters
        let modifiers = key.modifierFlags
        let isUndoLetter =
            key.keyCode == .keyboardZ || key.charactersIgnoringModifiers.lowercased() == "z"
        self.init(
            specialKey: specialKey,
            characters: characters,
            hasControlOrOption: !modifiers.isDisjoint(with: [.control, .alternate]),
            hasCommand: modifiers.contains(.command),
            hasShift: modifiers.contains(.shift),
            isUndoLetter: isUndoLetter)
    }

    private init?(
        specialKey: HardwareSpecialKey?,
        characters: String,
        hasControlOrOption: Bool,
        hasCommand: Bool,
        hasShift: Bool,
        isUndoLetter: Bool
    ) {
        guard !hasControlOrOption else { return nil }
        if hasCommand {
            guard !hasShift, isUndoLetter else { return nil }
            self = .undo
            return
        }
        if let specialKey {
            switch specialKey {
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
            case .enter:
                self = .toggleGroupFocus
                return
            case .escape:
                self = .collapseGroup
                return
            }
        }
        switch characters.lowercased() {
        case "0", "1", "2", "3", "4", "5":
            guard let level = Int(characters).flatMap(Rating.init(rawValue:)) else {
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
