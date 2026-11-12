import Foundation
import Synchronization
import Testing

@testable import CloveImaging

/// These controls block Dispatch threads, not the Swift cooperative executor.
/// Deadlines bound a regression failure; no performance threshold is asserted.
private final class ThumbnailIOGate: Sendable {
    private let armed = Mutex(false)
    private let entry = AsyncStream<Void>.makeStream()
    private let released = DispatchSemaphore(value: 0)

    func arm() { armed.withLock { $0 = true } }
    func pauseIfArmed() {
        let pause = armed.withLock { armed in
            let value = armed
            armed = false
            return value
        }
        guard pause else { return }
        entry.continuation.yield(())
        #expect(released.wait(timeout: .now() + 10) == .success)
    }
    func waitForEntry() async {
        var entries = entry.stream.makeAsyncIterator()
        await entries.next()
    }
    func release() { released.signal() }
}

private final class ThumbnailCacheOperation<Value: Sendable>: Sendable {
    private let completion = DispatchGroup()
    private let result = Mutex<Result<Value, any Error>?>(nil)

    init(_ operation: @escaping @Sendable () throws -> Value) {
        completion.enter()
        DispatchQueue.global().async { [self] in
            let value = Result { try operation() }
            result.withLock { $0 = value }
            completion.leave()
        }
    }

    func value() async throws -> Value {
        await withCheckedContinuation { continuation in
            completion.notify(queue: .global()) { continuation.resume() }
        }
        return try #require(result.withLock { $0 }).get()
    }
}

struct ThumbnailCacheConcurrencyTests {
    @Test func pausedStoreAllowsUnrelatedMemoryAndDiskHits() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let diskRequest = try thumbnailRequest(directory.image(name: "disk.jpg"))
        let memoryRequest = try thumbnailRequest(directory.image(name: "memory.jpg"))
        let storeRequest = try thumbnailRequest(directory.image(name: "store.jpg"))
        let image = ThumbnailExtractor().extract(diskRequest)
        let gate = ThumbnailIOGate()
        let cache = try ThumbnailCache(
            directory: directory.url.appendingPathComponent("cache"), configuration: .init(),
            beforeCommit: { _ in gate.pauseIfArmed() })
        try cache.store(image, for: diskRequest)
        cache.releaseMemory()
        try cache.store(image, for: memoryRequest)
        gate.arm()
        let store = ThumbnailCacheOperation { try cache.store(image, for: storeRequest) }
        defer { gate.release() }
        await gate.waitForEntry()
        let memoryHit = ThumbnailCacheOperation { cache.result(for: memoryRequest) }
        let diskHit = ThumbnailCacheOperation { cache.result(for: diskRequest) }
        #expect(try await memoryHit.value() != nil)
        #expect(try await diskHit.value() != nil)
        // Both lookups completed while the store is still inside beforeCommit.
        gate.release()
        try await store.value()
        #expect(cache.result(for: storeRequest) != nil)
    }

    @Test func concurrentStoresOfOneKeyPublishLastWriterAndKeepByteCostsCorrect() async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let request = try thumbnailRequest(directory.image())
        let large = ThumbnailExtractor().extract(request)
        let small = ThumbnailExtractor().extract(try thumbnailRequest(request.source, pixels: 200))
        let calibration = try directory.cache(memory: 0)
        try calibration.store(large, for: request)
        let cacheURL = directory.url.appendingPathComponent("cache")
        let file = try #require(
            FileManager.default.contentsOfDirectory(
                at: cacheURL, includingPropertiesForKeys: nil
            ).first)
        let size = try Data(contentsOf: file).count
        var configuration = ThumbnailCache.Configuration()
        configuration.diskBytes = size * 2
        let gate = ThumbnailIOGate()
        let cache = try ThumbnailCache(
            directory: cacheURL, configuration: configuration,
            beforeCommit: { _ in gate.pauseIfArmed() })
        gate.arm()
        let lastWriter = ThumbnailCacheOperation { try cache.store(large, for: request) }
        defer { gate.release() }
        await gate.waitForEntry()
        // This store begins later, but publishes before the paused writer.
        let firstWriter = ThumbnailCacheOperation { try cache.store(small, for: request) }
        try await firstWriter.value()
        let interim = try availableThumbnail(#require(cache.result(for: request)))
        #expect(max(interim.width, interim.height) == 200)
        gate.release()
        try await lastWriter.value()
        let memory = try availableThumbnail(#require(cache.result(for: request)))
        #expect(max(memory.width, memory.height) == 400)
        cache.releaseMemory()
        let disk = try availableThumbnail(#require(cache.result(for: request)))
        #expect(max(disk.width, disk.height) == 400)
        let second = try thumbnailRequest(directory.image(name: "second.jpg"))
        try cache.store(large, for: second)
        cache.releaseMemory()
        #expect(cache.result(for: request) != nil)
        #expect(cache.result(for: second) != nil)
        let third = try thumbnailRequest(directory.image(name: "third.jpg"))
        try cache.store(large, for: third)
        cache.releaseMemory()
        #expect(cache.result(for: request) == nil)
        #expect(cache.result(for: second) != nil)
        #expect(cache.result(for: third) != nil)
        let files = try FileManager.default.contentsOfDirectory(
            at: cacheURL, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        #expect(try files.reduce(0) { try $0 + Data(contentsOf: $1).count } == size * 2)
        let reopened = try directory.cache(memory: 0, disk: size * 2)
        #expect(reopened.result(for: request) == nil)
        #expect(reopened.result(for: second) != nil)
        #expect(reopened.result(for: third) != nil)
    }

    @Test func evictionDuringDiskDecodeReturnsMissWithoutPromotingStalePixels() async throws {
        try await invalidatedDiskRead(replaceSameKey: false)
    }

    @Test func replacementDuringDiskDecodeReturnsMissAndKeepsNewerFile() async throws {
        try await invalidatedDiskRead(replaceSameKey: true)
    }

    private func invalidatedDiskRead(replaceSameKey: Bool) async throws {
        let directory = try ThumbnailTestDirectory()
        defer { directory.remove() }
        let request = try thumbnailRequest(directory.image())
        let image = ThumbnailExtractor().extract(request)
        let calibration = try directory.cache(memory: 0)
        try calibration.store(image, for: request)
        let cacheURL = directory.url.appendingPathComponent("cache")
        let file = try #require(
            FileManager.default.contentsOfDirectory(
                at: cacheURL, includingPropertiesForKeys: nil
            ).first)
        let size = try Data(contentsOf: file).count
        var configuration = ThumbnailCache.Configuration()
        configuration.memoryBytes = 0
        configuration.diskBytes = size
        let gate = ThumbnailIOGate()
        let cache = try ThumbnailCache(
            directory: cacheURL, configuration: configuration,
            beforeCommit: { _ in }, afterDecode: { gate.pauseIfArmed() })
        gate.arm()
        let reading = ThumbnailCacheOperation { cache.result(for: request) }
        defer { gate.release() }
        await gate.waitForEntry()
        let newer: ThumbnailRequest
        let newImage: ThumbnailResult
        if replaceSameKey {
            newer = request
            newImage = ThumbnailExtractor().extract(
                try thumbnailRequest(request.source, pixels: 200))
        } else {
            newer = try thumbnailRequest(directory.image(name: "newer.jpg"))
            newImage = image
        }
        let writing = ThumbnailCacheOperation { try cache.store(newImage, for: newer) }
        try await writing.value()
        gate.release()
        #expect(try await reading.value() == nil)
        let current = try availableThumbnail(#require(cache.result(for: newer)))
        #expect(max(current.width, current.height) == (replaceSameKey ? 200 : 400))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cacheURL.path).count == 1)
    }
}
