import Foundation

/// Delivers a scan to a consumer in batches, the way the grid would receive
/// results while a card is still being read.
public enum ScanStream {
    /// Scans `folder` and streams paired photos in batches.
    ///
    /// The walk runs on a detached task; the caller's task consumes the stream.
    /// Batch times are measured from the start of the walk: `produced` when the
    /// walk finishes a batch, `received` when the consumer's loop sees it.
    ///
    /// - Parameters:
    ///   - folder: Root of the tree to scan.
    ///   - method: Listing method to stream with.
    ///   - keySet: Resource keys to fetch.
    ///   - options: Filters and batch size.
    /// - Returns: The full listing and what the stream observed.
    public static func run(
        folder: URL,
        method: ScanMethod,
        keySet: ScanKeySet = .all,
        options: ScanOptions = ScanOptions()
    ) async throws -> (listing: ScanListing, report: ScanStreamReport) {
        let start = ContinuousClock.now
        let (stream, continuation) = AsyncStream<ScanStreamBatch>.makeStream()
        let producer = Task.detached(priority: .userInitiated) { () throws -> ScanListing in
            do {
                let listing = try ScanLister.list(
                    folder: folder, method: method, keySet: keySet, options: options
                ) { batch in
                    let photos = ScanPairing.photos(from: batch.entries)
                    continuation.yield(
                        ScanStreamBatch(
                            photos: photos, number: batch.number,
                            producedMilliseconds: ScanClock.milliseconds(from: start)))
                }
                continuation.finish()
                return listing
            } catch {
                continuation.finish()
                throw error
            }
        }

        var received: [ScanStreamBatch] = []
        for await batch in stream {
            if Task.isCancelled {
                producer.cancel()
                break
            }
            var batch = batch
            batch.receivedMilliseconds = ScanClock.milliseconds(from: start)
            received.append(batch)
        }
        let listing = try await producer.value
        var report = ScanStreamReport(
            batches: received.count,
            files: listing.entries.count,
            firstBatchProducedMilliseconds: received.first?.producedMilliseconds,
            firstBatchReceivedMilliseconds: received.first?.receivedMilliseconds,
            lastBatchReceivedMilliseconds: received.last?.receivedMilliseconds
        )
        report.firstHundredMilliseconds = listing.firstHundredMilliseconds
        return (listing, report)
    }
}
