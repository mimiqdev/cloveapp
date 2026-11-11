/// Folder access problems and their available actions.
public enum SaveSituation: String, CaseIterable, Hashable, Sendable {
    case lostPermission
    case locationUnavailable
    case driveDisconnected

    public var message: String {
        switch self {
        case .lostPermission:
            "Access to this folder is no longer available. Open it again."
        case .locationUnavailable:
            "This location can't be found. Select it again through Open."
        case .driveDisconnected:
            "The drive disconnected. Reconnect it, then reopen this folder."
        }
    }

    public var actions: [SaveAction] {
        switch self {
        case .lostPermission, .driveDisconnected: [.reopenFolder]
        case .locationUnavailable: [.openFolder]
        }
    }
}

public enum SaveAction: String, CaseIterable, Hashable, Sendable {
    case reopenFolder
    case openFolder

    public var title: String {
        switch self {
        case .reopenFolder: "Reopen folder"
        case .openFolder: "Open folder…"
        }
    }
}
