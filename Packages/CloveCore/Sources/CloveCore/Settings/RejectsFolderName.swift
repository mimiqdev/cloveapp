/// Why a proposed rejects folder name was refused (PRD Move rejects).
public enum RejectsFolderNameError: Error, Hashable, Sendable {
    /// The name is empty.
    case empty
    /// The name contains a path separator, so it would name more than one component.
    case pathSeparator
    /// The name is `.` or `..`, which name the current or parent folder.
    case relativeComponent
    /// The name starts with a dot, so the system would treat the folder as hidden.
    case hidden
    /// The name contains a control character, which no visible folder name should carry.
    case controlCharacter
    /// The name is longer than `RejectsFolderName.maximumUTF8Length` bytes.
    case tooLong
}

/// A validated single path component used as the Move rejects destination folder name.
///
/// The launch default is `_Rejected` (PRD Move rejects). Validation refuses an invalid name
/// instead of trimming, replacing, or otherwise changing it, so the user sees the problem and
/// picks a new name. The name is only the last component; it is joined to each opened folder
/// and never contains a path.
public struct RejectsFolderName: RawRepresentable, Hashable, Sendable {
    /// The longest accepted name, measured in UTF-8 bytes, well inside filesystem limits.
    public static let maximumUTF8Length = 64

    /// The name exactly as validated; no normalization or trimming is applied.
    public let rawValue: String

    /// The launch default from PRD Move rejects.
    public static let defaultFolderName = RejectsFolderName(validText: "_Rejected")

    /// Refuses anything that is not one safe, visible path component (PRD Move rejects).
    ///
    /// The checks are: not empty, no `/`, not `.` or `..`, no leading dot, no control
    /// characters, and at most `maximumUTF8Length` UTF-8 bytes. Other text, including spaces
    /// and any script, is kept exactly as supplied.
    public init?(rawValue: String) {
        guard let name = try? RejectsFolderName.validated(rawValue) else { return nil }
        self = name
    }

    /// Validates a proposed name and reports why it was refused (PRD Move rejects).
    public static func validated(
        _ text: String
    ) throws(RejectsFolderNameError) -> RejectsFolderName {
        guard !text.isEmpty else { throw .empty }
        guard !text.contains("/") else { throw .pathSeparator }
        guard text != ".", text != ".." else { throw .relativeComponent }
        guard !text.hasPrefix(".") else { throw .hidden }
        guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw .controlCharacter }
        guard text.utf8.count <= maximumUTF8Length else { throw .tooLong }
        return RejectsFolderName(validText: text)
    }

    private init(validText: String) {
        self.rawValue = validText
    }
}
