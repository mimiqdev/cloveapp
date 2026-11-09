import Foundation
import Testing

@testable import FolderAccessProbe

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "clove-folder-access-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func bookmarksRoundTripAndRefreshPreservesRecordIdentity() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for minimal in [false, true] {
        let data = try AccessBookmark.encode(folder, minimal: minimal)
        let resolved = try AccessBookmark.resolve(data)
        #expect(resolved.url.standardizedFileURL == folder.standardizedFileURL)
        #expect(!resolved.stale)
        let original = AccessRecent(
            bookmark: data, pathSummary: "old path", media: .sdCard, photoCount: 12)
        let refreshed = try AccessBookmark.refreshed(original, at: folder)
        #expect(refreshed.id == original.id)
        #expect(refreshed.media == .sdCard)
        #expect(refreshed.photoCount == 12)
        #expect(refreshed.pathSummary == folder.path)
        #expect(
            try AccessBookmark.resolve(refreshed.bookmark).url.standardizedFileURL
                == folder.standardizedFileURL)
    }
}

@Test func movedBookmarkIsRefreshedAfterSuccessfulRead() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original")
    let moved = root.appendingPathComponent("moved")
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    let store = root.appendingPathComponent("recents.json")
    let experiment = AccessExperiment(storeURL: store)
    _ = await experiment.load()
    let picked = await experiment.pick(original, media: .local)
    let record = try #require(picked.recents.first)
    try FileManager.default.moveItem(at: original, to: moved)
    let reopened = await experiment.reopen(record.id)
    #expect(
        reopened.events.contains {
            $0.phase == .bookmarkCreate && $0.detail.contains("Re-created stale")
        })
    let saved = try #require(AccessRecents.load(from: store).records.first)
    let resolved = try AccessBookmark.resolve(saved.bookmark)
    #expect(!resolved.stale)
    #expect(resolved.url.standardizedFileURL == moved.standardizedFileURL)
}

@Test func corruptBookmarkFailsRatherThanResolvingAnUnrelatedPath() {
    #expect(throws: (any Error).self) { try AccessBookmark.resolve(Data("invalid bookmark".utf8)) }
}

@Test func recentsPersistTwoSameNameVolumesAndRejectCorruption() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("nested/recents.json")
    #expect(try AccessRecents.load(from: file).records.isEmpty)
    let records = AccessRecents(records: [
        AccessRecent(
            bookmark: Data([1]), pathSummary: "/Volumes/CARD/DCIM", volumeName: "CARD",
            volumeUUID: "A", media: .sdCard),
        AccessRecent(
            bookmark: Data([2]), pathSummary: "/Volumes/CARD/DCIM", volumeName: "CARD",
            volumeUUID: "B", media: .sdCard),
    ])
    try records.save(to: file)
    #expect(try AccessRecents.load(from: file) == records)
    try Data("{}".utf8).write(to: file)
    #expect(throws: (any Error).self) { try AccessRecents.load(from: file) }
    try Data("{\"schemaVersion\":99,\"records\":[]}".utf8).write(to: file)
    #expect(throws: (any Error).self) { try AccessRecents.load(from: file) }
}

@Test(arguments: [
    (NSPOSIXErrorDomain, 28, AccessFailure.full),
    (NSCocoaErrorDomain, 640, .full),
    (NSPOSIXErrorDomain, 30, .readOnly),
    (NSCocoaErrorDomain, 642, .readOnly),
    (NSPOSIXErrorDomain, 13, .permission),
    (NSPOSIXErrorDomain, 1, .permission),
    (NSCocoaErrorDomain, 257, .permission),
    (NSCocoaErrorDomain, 513, .permission),
    (NSCocoaErrorDomain, 260, .missingLocation),
    (NSPOSIXErrorDomain, 2, .missingLocation),
    ("provider.custom", 42, .unknown),
])
func errorMapping(domain: String, code: Int, expected: AccessFailure) {
    let error = AccessError(NSError(domain: domain, code: code))
    #expect(error.classify() == expected)
}

@Test func underlyingErrorWinsOverGenericWrapperAndMissingNeedsSessionContext() {
    let nested = NSError(domain: NSPOSIXErrorDomain, code: 28)
    let wrapped = AccessError(
        NSError(domain: NSCocoaErrorDomain, code: 512, userInfo: [NSUnderlyingErrorKey: nested]))
    #expect(wrapped.classify() == .full)
    #expect(wrapped.underlying.first?.code == 28)
    let missing = AccessError(NSError(domain: NSPOSIXErrorDomain, code: 2))
    #expect(missing.classify(knownExternal: true) == .missingLocation)
    #expect(missing.classify(previouslyReachable: true) == .missingLocation)
    #expect(missing.classify(knownExternal: true, previouslyReachable: true) == .missingLocation)
    #expect(
        missing.classify(knownExternal: true, previouslyReachable: true, volumeUnavailable: true)
            == .disconnected)
    #expect(
        AccessError(NSError(domain: NSPOSIXErrorDomain, code: 5)).classify(
            knownExternal: true, previouslyReachable: true) == .unknown)
}

@Test func writeProbeConfirmsBytesAndOnlyRemovesItsOwnFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let lab = folder.appendingPathComponent("clove-lab-folder-access")
    try FileManager.default.createDirectory(at: lab, withIntermediateDirectories: true)
    let sentinel = lab.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: sentinel)
    let result = AccessProbes.run(at: folder, write: true)
    #expect(result.events.filter { $0.phase == .write }.allSatisfy { $0.error == nil })
    #expect(result.events.contains { $0.phase == .write && $0.detail.contains("confirmed") })
    #expect(try FileManager.default.contentsOfDirectory(atPath: lab.path) == ["keep.txt"])
    #expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
}

@Test func fillAllocationAndCleanupAreBoundedAndPreserveOtherFiles() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let events = AccessFill.add(at: folder, maximumBytes: 2_048)
    #expect(events.allSatisfy { $0.error == nil })
    let lab = folder.appendingPathComponent("clove-lab-folder-access")
    let files = try FileManager.default.contentsOfDirectory(
        at: lab, includingPropertiesForKeys: nil)
    let fill = try #require(files.first)
    #expect(try Data(contentsOf: fill).count == 2_048)
    let sentinel = lab.appendingPathComponent("fill-folder-access-not-a-uuid.bin")
    try Data([1]).write(to: sentinel)
    #expect(AccessFill.clean(at: folder).allSatisfy { $0.error == nil })
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: lab.path) == [
            sentinel.lastPathComponent
        ])
}

@Test func deletedFolderReportsReadFailureAndKeepsExactSystemError() throws {
    let folder = try temporaryFolder()
    try FileManager.default.removeItem(at: folder)
    let result = AccessProbes.run(at: folder, write: false)
    let error = try #require(result.events.first { $0.phase == .read }?.error)
    #expect(error.classify() == .missingLocation)
    print("Folder access deleted-folder read: \(error.summary)")
}

@Test func watchDoesNotCallFolderDeletionADisconnectedExternalVolume() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let experiment = AccessExperiment(storeURL: folder.appendingPathComponent("recents.json"))
    _ = await experiment.load()
    // Label this local folder external to exercise the connected-volume guard.
    _ = await experiment.pick(folder, media: .sdCard)
    _ = await experiment.startWatch()
    _ = await experiment.markDisconnect()
    try FileManager.default.removeItem(at: folder)
    let snapshot = await experiment.poll()
    await experiment.stopWatch()
    #expect(snapshot.report.measurements.contains { $0.name == "unreachable-since-last-success" })
    #expect(
        snapshot.events.contains {
            $0.phase == .watch && $0.detail.contains("Remembered location unavailable")
        })
}
