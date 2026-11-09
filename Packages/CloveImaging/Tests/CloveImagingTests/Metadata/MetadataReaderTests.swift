import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CloveImaging

private func generatedJPEG(in folder: URL, name: String, exif: [String: Any] = [:]) throws -> URL {
    let url = folder.appendingPathComponent(name).appendingPathExtension("jpg")
    let context = try #require(
        CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
    let image = try #require(context.makeImage())
    let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(
        destination, image, [kCGImagePropertyExifDictionary: exif] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    try FileManager.default.setAttributes(
        [
            .creationDate: Date(timeIntervalSince1970: 1_600_000_000),
            .modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
        ], ofItemAtPath: url.path)
    return url
}

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func success(_ outcome: MetadataReadOutcome) throws -> ImageMetadata {
    guard case .success(let metadata) = outcome else {
        Issue.record("Expected successful metadata read, got \(outcome)")
        throw CocoaError(.fileReadUnknown)
    }
    return metadata
}

@Test func generatedCaptureAndFileTimeFallbacks() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let captureURL = try generatedJPEG(
        in: folder, name: "capture",
        exif: [
            "DateTimeOriginal": "2024:02:29 12:34:56", "SubsecTimeOriginal": "007",
            "OffsetTimeOriginal": "+05:30",
        ])
    let capture = try success(MetadataReader().read(url: captureURL).outcome)
    #expect(capture.captureTime.value != nil)
    #expect(capture.subseconds.value == "007")
    #expect(capture.utcOffset.value == 19800)
    #expect(capture.captureTime.source == .imageProperty("{Exif}.DateTimeOriginal"))
    #expect(capture.time == .captureMetadata(try #require(capture.captureTime.value)))

    let noExifURL = try generatedJPEG(in: folder, name: "no-exif")
    let noExif = try success(MetadataReader().read(url: noExifURL).outcome)
    #expect(noExif.captureTime == .missing)
    #expect(noExif.time == .fileCreation(Date(timeIntervalSince1970: 1_600_000_000)))
    #expect(noExif.fileCreationTime.source == .fileCreation)
    #expect(noExif.fileModificationTime.value == Date(timeIntervalSince1970: 1_700_000_000))

    // APFS always supplies birth time. Model a provider that omits it, while reading
    // the generated JPEG and its real, controlled modification date through the same loader.
    let modification = try success(
        MetadataReader.load(noExifURL) { url in
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return (nil, values.contentModificationDate)
        })
    #expect(modification.fileCreationTime == .missing)
    #expect(modification.time == .fileModification(Date(timeIntervalSince1970: 1_700_000_000)))
    let undated = try success(MetadataReader.load(noExifURL) { _ in (nil, nil) })
    #expect(undated.time == .unavailable)
    let inaccessibleDates = try success(
        MetadataReader.load(captureURL) { _ in throw CocoaError(.fileReadNoPermission) })
    #expect(inaccessibleDates.captureTime == capture.captureTime)
    #expect(inaccessibleDates.fileCreationTime == .missing)
}

@Test func unreadableFileDoesNotFailBatch() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let valid = try generatedJPEG(in: folder, name: "valid")
    let missing = folder.appendingPathComponent("missing.jpg")
    let corrupt = folder.appendingPathComponent("corrupt.jpg")
    try Data("not an image".utf8).write(to: corrupt)
    let urls = [valid, missing, corrupt, valid]
    let results = await MetadataReader(maximumConcurrentReads: 2).read(urls: urls)
    #expect(results.map(\.url) == urls)
    #expect(try success(results[0].outcome).captureTime == .missing)
    #expect(results[1].outcome == .failure(.unreadableFile))
    #expect(results[2].outcome == .failure(.propertiesUnavailable))
    #expect(results[3] == results[0])
    #expect(await MetadataReader().read(urls: []).isEmpty)
}

/// Gates the initial worker wave without using timing assumptions to assert cancellation.
private final class ReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var count = 0
    private var active = 0
    private var peak = 0
    private var started: CheckedContinuation<Void, Never>?

    func waitForWorkers() async {
        await withCheckedContinuation { continuation in
            let alreadyStarted = lock.withLock {
                if count >= 2 { return true }
                started = continuation
                return false
            }
            if alreadyStarted { continuation.resume() }
        }
    }

    func read(_ url: URL) -> MetadataReadOutcome {
        let notify: CheckedContinuation<Void, Never>? = lock.withLock {
            count += 1
            active += 1
            peak = max(peak, active)
            if count == 2 {
                defer { started = nil }
                return started
            }
            return nil
        }
        notify?.resume()
        let released = release.wait(timeout: .now() + 10) == .success
        #expect(released)
        lock.withLock { active -= 1 }
        return .failure(.propertiesUnavailable)
    }

    func open(count: Int) {
        for _ in 0..<count { release.signal() }
    }

    var counts: (reads: Int, peak: Int) { lock.withLock { (count, peak) } }
}

@Test func boundedBatchAndCancellation() async {
    let urls = (0..<12).map { URL(fileURLWithPath: "/\($0).jpg") }
    let gate = ReadGate()
    let reader = MetadataReader(maximumConcurrentReads: 2, readFile: gate.read)
    let batch = Task { await reader.read(urls: urls) }
    await gate.waitForWorkers()
    #expect(gate.counts.reads == 2)
    batch.cancel()
    gate.open(count: 2)
    let results = await batch.value
    #expect(results.map(\.url) == urls)
    #expect(results.allSatisfy { $0.outcome == .failure(.cancelled) })
    #expect(gate.counts.reads == 2)
    #expect(gate.counts.peak == 2)
}

@Test func boundedBatchReplenishesWorkersAndKeepsEveryInput() async {
    let urls = (0..<12).map { URL(fileURLWithPath: "/\($0).jpg") }
    let gate = ReadGate()
    let reader = MetadataReader(maximumConcurrentReads: 2, readFile: gate.read)
    let batch = Task { await reader.read(urls: urls) }
    await gate.waitForWorkers()
    #expect(gate.counts.reads == 2)
    gate.open(count: urls.count)
    let results = await batch.value
    #expect(results.map(\.url) == urls)
    #expect(results.allSatisfy { $0.outcome == .failure(.propertiesUnavailable) })
    #expect(gate.counts.reads == urls.count)
    #expect(gate.counts.peak == 2)
}

@Test func alreadyCancelledBatchDoesNoIO() async {
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await MetadataReader(maximumConcurrentReads: 1) { _ in
            Issue.record("Cancelled batch admitted I/O")
            return .failure(.propertiesUnavailable)
        }.read(urls: [URL(fileURLWithPath: "/unused.jpg")])
    }
    #expect(await task.value.map(\.outcome) == [.failure(.cancelled)])
}
