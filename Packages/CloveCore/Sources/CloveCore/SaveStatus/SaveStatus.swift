/// Maps folder access failures to the explanation shown on entry and while browsing.
public enum SaveStatus {
    public static func situation(for loss: FolderLocationLoss) -> SaveSituation {
        switch loss.reason {
        case .externalVolumeDisconnected: .driveDisconnected
        case .locationUnavailable: .locationUnavailable
        }
    }

    public static func situation(for failure: FolderAccessFailure) -> SaveSituation? {
        switch failure {
        case .locationUnavailable: .locationUnavailable
        case .permissionDenied: .lostPermission
        case .identityMismatch, .readFailed, .storageUnavailable, .unknownRecent: nil
        }
    }
}
