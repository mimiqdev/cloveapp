import Foundation

/// The one join between C12's settings and C2's walk: the rejects folder name they share.
///
/// G1 decision 5 makes the scan skip the rejects folder so a moved photo is not listed twice,
/// and PRD Move rejects lets the user rename that folder in Settings. C2 already takes the name
/// as a ``ScanConfiguration`` option and C12 already validates it as a ``RejectsFolderName``, so
/// this property is the smallest bridge: it hands the validated setting to the walk instead of
/// keeping a second default that could drift. Nothing else in either type changes.
extension AppSettings {
    /// The scan configuration that skips exactly the folder Move rejects writes into.
    ///
    /// Pass it to ``FolderScan`` so a rescan after a confirmed move lists no moved photo
    /// (PRD P0-10, G1 decision 5). The batch size stays C2's default.
    public var scanConfiguration: ScanConfiguration {
        ScanConfiguration(rejectsFolderName: rejectsFolderName.rawValue)
    }
}
