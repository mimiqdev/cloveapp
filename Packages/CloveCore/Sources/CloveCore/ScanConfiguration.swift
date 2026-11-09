import Foundation

/// Options for one folder scan; the defaults are the ones the PRD and G1 fix.
public struct ScanConfiguration: Hashable, Sendable {
    /// Folder name the walk skips at any depth, `_Rejected` by default (PRD scan scope).
    /// C12 turns it into a setting, so the scanner takes it as an option; G1 decision 5
    /// makes the scan skip that folder so moved rejects are not shown twice.
    public static let defaultRejectsFolderName = "_Rejected"

    /// Largest batch a scan delivers, fixed by G1's scan approach.
    public static let maximumBatchSize = 64

    /// Folder name treated as the rejects folder, matched without regard to case (PRD scan scope).
    public let rejectsFolderName: String

    /// Items per batch, clamped to 1 through ``maximumBatchSize`` (G1 scan approach: 64).
    public let batchSize: Int

    /// Configures one scan; `_Rejected` and 64 items are the defaults (PRD scan scope, G1 scan).
    public init(
        rejectsFolderName: String = ScanConfiguration.defaultRejectsFolderName,
        batchSize: Int = ScanConfiguration.maximumBatchSize
    ) {
        self.rejectsFolderName = rejectsFolderName
        self.batchSize = min(max(batchSize, 1), ScanConfiguration.maximumBatchSize)
    }
}
