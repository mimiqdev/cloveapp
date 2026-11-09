import Foundation

/// One scan of an opened folder: batches of results in walk order, then a summary.
///
/// The walk runs on a background task and streams as it goes (PRD scan scope, G1 scan
/// approach). Each batch holds at most ``ScanConfiguration/batchSize`` items, and no photo
/// set's members are ever split across batches. Consume the sequence, then call
/// ``summary()`` for the counts and status.
///
/// ```swift
/// let scan = FolderScan(folderURL: url, folderID: session.id)
/// for try await batch in scan {
///     // Show or forward `batch.items`; ordering is C8's job.
/// }
/// let summary = try await scan.summary()
/// ```
public struct FolderScan: AsyncSequence, Sendable {
    /// What one iteration yields: items in walk order (G1 scan approach).
    public typealias Element = ScanBatch

    private let stream: AsyncThrowingStream<ScanBatch, Error>
    private let producer: Task<ScanSummary, Error>

    /// Starts a scan of `folderURL`, which the caller can already read (PRD P0-02, G1 folder
    /// access). `folderID` is the caller's durable key and appears in every photo identity
    /// (C1, G1 decision 5).
    public init(
        folderURL: URL,
        folderID: FolderIdentity,
        configuration: ScanConfiguration = ScanConfiguration()
    ) {
        let walk = PhotoFolderWalk(
            rootURL: folderURL, folderID: folderID, configuration: configuration)
        let (stream, continuation) = AsyncThrowingStream<ScanBatch, Error>.makeStream()
        let producer = Task.detached(priority: .userInitiated) { () throws -> ScanSummary in
            do {
                let summary = try walk.run { batch in continuation.yield(batch) }
                continuation.finish()
                return summary
            } catch {
                continuation.finish(throwing: error)
                throw error
            }
        }
        // Leaving the sequence early, or cancelling its consumer, stops the walk
        // (PRD scan scope: the scan supports cancellation).
        continuation.onTermination = { _ in producer.cancel() }
        self.stream = stream
        self.producer = producer
    }

    /// Iterates the batches in walk order (G1 scan approach).
    public func makeAsyncIterator() -> AsyncThrowingStream<ScanBatch, Error>.AsyncIterator {
        stream.makeAsyncIterator()
    }

    /// Waits for the walk and reports its counts, status and read issues (PRD P0-01).
    /// Call it after the batch sequence ends; a cancelled walk throws `CancellationError`.
    public func summary() async throws -> ScanSummary {
        try await producer.value
    }
}
