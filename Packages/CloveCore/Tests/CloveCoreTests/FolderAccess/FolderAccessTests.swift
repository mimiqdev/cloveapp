import Foundation
import Testing

import CloveCore

private func makeAccess(
    storeRoot: URL,
    scope: ScopeRecorder,
    clock: TestClock = TestClock(),
    locations: any FolderLocationReading = FileSystemLocationReader()
) -> FolderAccess {
    FolderAccess(
        store: RecentFolderStore(fileURL: storeRoot.appendingPathComponent("recents.json")),
        scope: scope, locations: locations, now: { clock.now })
}

private func resolveBookmark(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
    var isStale = false
    let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing],
        relativeTo: nil, bookmarkDataIsStale: &isStale)
    return (url, isStale)
}

private func makeFolder(named name: String, in parent: URL) throws -> URL {
    let url = parent.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func pickingThenReopeningKeepsTheSameIdentity() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = try makeFolder(named: "DCIM", in: parent)

    let scope = ScopeRecorder()
    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: scope, clock: clock)

    let first = try #require(await access.pick(folder).openedFolder)
    #expect(first.recent.identity == FolderIdentity(rawValue: first.recent.id.uuidString))
    #expect(first.session.folder.id == first.recent.identity)
    #expect(isSameLocation(first.session.rootURL, folder))
    #expect(first.session.identityCheck == .verified)
    #expect(first.recent.lastOpened == clock.now)
    #expect(scope.startCount == 1)
    #expect(scope.stopCount == 0)

    await first.session.end()
    #expect(scope.stopCount == 1)

    clock.advance(60)
    let second = try #require(await access.reopen(first.recent.id).openedFolder)
    #expect(second.recent.id == first.recent.id)
    #expect(second.recent.lastOpened == clock.now)
    #expect(second.session.identityCheck == .verified)
    #expect(isSameLocation(second.session.rootURL, folder))
    await second.session.end()
    #expect(scope.startCount == 2)
    #expect(scope.stopCount == 2)

    #expect(try await access.recents().map(\.id) == [first.recent.id])
}

@Test func pickingTheSameFolderAgainReusesItsRecord() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = try makeFolder(named: "CARD", in: parent)

    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: ScopeRecorder(), clock: clock)
    let first = try #require(await access.pick(folder).openedFolder)
    try await access.recordScan(
        FolderScanSummary(photoCount: 7, status: .complete), for: first.session)
    await first.session.end()

    clock.advance(30)
    let second = try #require(await access.pick(folder).openedFolder)
    #expect(second.recent.id == first.recent.id)
    #expect(second.recent.photoCount == 7)
    #expect(second.recent.scanStatus == .complete)
    #expect(second.recent.lastOpened == clock.now)
    #expect(try await access.recents().count == 1)
}

@Test func theSameFolderNameInDifferentPlacesIsADifferentRecent() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let firstParent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: firstParent) }
    let secondParent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: secondParent) }
    let firstFolder = try makeFolder(named: "CARD", in: firstParent)
    let secondFolder = try makeFolder(named: "CARD", in: secondParent)

    let access = makeAccess(storeRoot: storeRoot, scope: ScopeRecorder())
    let first = try #require(await access.pick(firstFolder).openedFolder)
    let second = try #require(await access.pick(secondFolder).openedFolder)
    #expect(first.recent.id != second.recent.id)
    #expect(first.recent.volumeName == second.recent.volumeName)
    #expect(first.recent.pathSummary != second.recent.pathSummary)
    await first.session.end()
    await second.session.end()

    let recents = try await access.recents()
    #expect(Set(recents.map(\.id)) == [first.recent.id, second.recent.id])
    let reopened = try #require(await access.reopen(second.recent.id).openedFolder)
    #expect(isSameLocation(reopened.session.rootURL, secondFolder))
    await reopened.session.end()
}

@Test func aMovedFolderKeepsItsIdentityAndRefreshesTheBookmark() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let original = try makeFolder(named: "original", in: parent)
    let moved = parent.appendingPathComponent("renamed", isDirectory: true)

    let scope = ScopeRecorder()
    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: scope, clock: clock)
    let first = try #require(await access.pick(original).openedFolder)
    try await access.recordScan(
        FolderScanSummary(photoCount: 5, status: .complete), for: first.session)
    await first.session.end()
    let savedBefore = try #require(try await access.recents().first)
    #expect(try resolveBookmark(savedBefore.bookmark).isStale == false)

    try FileManager.default.moveItem(at: original, to: moved)
    #expect(try resolveBookmark(savedBefore.bookmark).isStale)

    clock.advance(120)
    let reopened = try #require(await access.reopen(savedBefore.id).openedFolder)
    #expect(reopened.recent.id == savedBefore.id)
    #expect(reopened.recent.photoCount == 5)
    #expect(reopened.session.identityCheck == .verified)
    #expect(isSameLocation(reopened.session.rootURL, moved))
    #expect(
        isSameLocation(
            URL(fileURLWithPath: reopened.recent.pathSummary, isDirectory: true), moved))
    await reopened.session.end()

    let savedAfter = try #require(try await access.recents().first)
    let resolution = try resolveBookmark(savedAfter.bookmark)
    #expect(!resolution.isStale)
    #expect(isSameLocation(resolution.url, moved))
    #expect(scope.startCount == scope.stopCount)
}

@Test func aDeletedFolderKeepsItsRecentAndLastOpenedTime() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = try makeFolder(named: "DCIM", in: parent)

    let scope = ScopeRecorder()
    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: scope, clock: clock)
    let opened = try #require(await access.pick(folder).openedFolder)
    try await access.recordScan(
        FolderScanSummary(photoCount: 3, status: .partial), for: opened.session)
    await opened.session.end()
    let before = try #require(try await access.recents().first)

    try FileManager.default.removeItem(at: folder)
    clock.advance(120)
    let failure = try #require(await access.reopen(before.id).failure)
    guard case .locationUnavailable(let chain) = failure else {
        Issue.record("expected a location-unavailable failure, got \(failure)")
        return
    }
    #expect(!chain.errors.isEmpty)
    #expect(try await access.recents() == [before])
    #expect(scope.startCount == scope.stopCount)
}

@Test func aFolderReplacedAtTheSamePathIsAnIdentityMismatch() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = try makeFolder(named: "DCIM", in: parent)

    let scope = ScopeRecorder()
    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: scope, clock: clock)
    let opened = try #require(await access.pick(folder).openedFolder)
    await opened.session.end()
    let before = try #require(try await access.recents().first)

    try FileManager.default.removeItem(at: folder)
    _ = try makeFolder(named: "DCIM", in: parent)
    clock.advance(120)
    let failure = try #require(await access.reopen(before.id).failure)
    guard case .identityMismatch(let recorded, let found) = failure else {
        Issue.record("expected an identity mismatch, got \(failure)")
        return
    }
    #expect(recorded == before.identityKeys)
    #expect(recorded.volumeUUID == found.volumeUUID)
    #expect(recorded.fileIdentifier != found.fileIdentifier)

    let after = try #require(try await access.recents().first)
    #expect(after == before)
    #expect(after.lastOpened == before.lastOpened)
    // The old bookmark now resolves the replacement, so only the identity check kept it out.
    let resolution = try resolveBookmark(before.bookmark)
    #expect(resolution.isStale)
    #expect(isSameLocation(resolution.url, folder))
    #expect(scope.startCount == scope.stopCount)
}

@Test func failedValidationDoesNotRefreshAStaleBookmark() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let original = try makeFolder(named: "original", in: parent)
    let moved = parent.appendingPathComponent("renamed", isDirectory: true)

    let scope = ScopeRecorder()
    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: scope, clock: clock)
    let opened = try #require(await access.pick(original).openedFolder)
    await opened.session.end()
    let before = try #require(try await access.recents().first)

    try FileManager.default.moveItem(at: original, to: moved)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o000], ofItemAtPath: moved.path)
    defer {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: moved.path)
    }
    clock.advance(120)

    let failure = try #require(await access.reopen(before.id).failure)
    guard case .permissionDenied(let chain) = failure else {
        Issue.record("expected a permission failure, got \(failure)")
        return
    }
    #expect(
        chain.errors.contains {
            $0.matches(domain: NSCocoaErrorDomain, code: 257)
                || $0.matches(domain: NSPOSIXErrorDomain, code: 13)
        })
    let after = try #require(try await access.recents().first)
    #expect(after.bookmark == before.bookmark)
    #expect(after.lastOpened == before.lastOpened)
    #expect(scope.startCount == scope.stopCount)
}

@Test func aRecordWithoutIdentityKeysOpensProvisionally() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let folder = try makeFolder(named: "DCIM", in: parent)
    let record = RecentFolder(
        bookmark: try folder.bookmarkData(), pathSummary: folder.path,
        identityKeys: FolderIdentityKeys())
    let store = RecentFolderStore(fileURL: storeRoot.appendingPathComponent("recents.json"))
    try store.save([record])

    let scope = ScopeRecorder()
    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: scope, clock: clock)
    let opened = try #require(await access.reopen(record.id).openedFolder)
    #expect(opened.session.identityCheck == .weak)
    #expect(isSameLocation(opened.session.rootURL, folder))
    await opened.session.end()

    let saved = try #require(try await access.recents().first)
    #expect(saved.id == record.id)
    #expect(saved.identityKeys.volumeUUID != nil)
    #expect(saved.identityKeys.fileIdentifier != nil)
    #expect(saved.lastOpened == clock.now)
    #expect(scope.startCount == 1)
    #expect(scope.stopCount == 1)
}

@Test func aProviderReadFailureKeepsItsExactError() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let scope = ScopeRecorder()
    let access = makeAccess(
        storeRoot: storeRoot, scope: scope,
        locations: FailingReadLocationReader(domain: "com.clove.provider", code: 42))
    let failure = try #require(await access.pick(folder).failure)
    guard case .readFailed(let chain) = failure else {
        Issue.record("expected a read failure, got \(failure)")
        return
    }
    #expect(chain.domain == "com.clove.provider")
    #expect(chain.code == 42)
    #expect(chain.message == "The provider refused the read.")
    #expect(scope.startCount == 1)
    #expect(scope.stopCount == 1)
    #expect(try await access.recents().isEmpty)
}

@Test func aMissingFolderSelectedAgainIsReportedAsUnavailable() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let parent = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: parent) }
    let missing = parent.appendingPathComponent("gone", isDirectory: true)

    let scope = ScopeRecorder()
    let access = makeAccess(storeRoot: storeRoot, scope: scope)
    let failure = try #require(await access.pick(missing).failure)
    guard case .locationUnavailable(let chain) = failure else {
        Issue.record("expected a location-unavailable failure, got \(failure)")
        return
    }
    #expect(
        chain.errors.contains {
            $0.matches(domain: NSCocoaErrorDomain, code: 260)
                || $0.matches(domain: NSPOSIXErrorDomain, code: 2)
        })
    #expect(scope.startCount == 1)
    #expect(scope.stopCount == 1)
    #expect(try await access.recents().isEmpty)
}

@Test func anUnknownRecentTouchesNothing() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let access = makeAccess(storeRoot: storeRoot, scope: ScopeRecorder())
    let missing = UUID()
    #expect(await access.reopen(missing).failure == .unknownRecent(missing))
    #expect(try await access.recents().isEmpty)
}

@Test func corruptStorageIsReportedAndNeverOverwritten() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = storeRoot.appendingPathComponent("recents.json")
    let corrupt = Data("{\"version\":1,\"folders\":[".utf8)
    try corrupt.write(to: file)

    let scope = ScopeRecorder()
    let access = makeAccess(storeRoot: storeRoot, scope: scope)
    do {
        _ = try await access.recents()
        Issue.record("expected corrupt storage to be reported")
    } catch let error as RecentFolderStoreError {
        guard case .unreadable = error else {
            Issue.record("expected an unreadable error, got \(error)")
            return
        }
    }

    let failure = try #require(await access.pick(folder).failure)
    guard case .storageUnavailable(.unreadable(let chain)) = failure else {
        Issue.record("expected a storage failure, got \(failure)")
        return
    }
    #expect(!chain.errors.isEmpty)
    #expect(try Data(contentsOf: file) == corrupt)
    #expect(scope.startCount == 1)
    #expect(scope.stopCount == 1)
}

@Test func aNewerRecentsSchemaIsNotOverwritten() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = storeRoot.appendingPathComponent("recents.json")
    let newer = Data(#"{"version":99,"folders":[]}"#.utf8)
    try newer.write(to: file)

    let access = makeAccess(storeRoot: storeRoot, scope: ScopeRecorder())
    let failure = try #require(await access.pick(folder).failure)
    #expect(failure == .storageUnavailable(.unsupportedVersion(99)))
    #expect(try Data(contentsOf: file) == newer)
}

@Test func scanResultsUpdateCountStatusAndLastOpened() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let clock = TestClock()
    let access = makeAccess(storeRoot: storeRoot, scope: ScopeRecorder(), clock: clock)
    let opened = try #require(await access.pick(folder).openedFolder)

    clock.advance(5)
    try await access.recordScan(
        FolderScanSummary(photoCount: 1_200, status: .complete), for: opened.session)
    let complete = try #require(try await access.recents().first)
    #expect(complete.photoCount == 1_200)
    #expect(complete.scanStatus == .complete)
    #expect(complete.lastOpened == clock.now)

    clock.advance(5)
    try await access.recordScan(
        FolderScanSummary(photoCount: 900, status: .partial), for: opened.session)
    let partial = try #require(try await access.recents().first)
    #expect(partial.photoCount == 900)
    #expect(partial.scanStatus == .partial)
    #expect(partial.lastOpened == clock.now)
    #expect(partial.bookmark == complete.bookmark)

    await opened.session.end()
    let reloaded = makeAccess(storeRoot: storeRoot, scope: ScopeRecorder())
    let records = try await reloaded.recents()
    #expect(records.first?.photoCount == 900)
    #expect(records.first?.scanStatus == .partial)
}

@Test func aScanUpdateDoesNotOverwriteCorruptStorage() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = storeRoot.appendingPathComponent("recents.json")

    let access = makeAccess(storeRoot: storeRoot, scope: ScopeRecorder())
    let opened = try #require(await access.pick(folder).openedFolder)
    let corrupt = Data("not json".utf8)
    try corrupt.write(to: file)

    do {
        try await access.recordScan(
            FolderScanSummary(photoCount: 1, status: .complete), for: opened.session)
        Issue.record("expected the corrupt store to be reported")
    } catch let error as RecentFolderStoreError {
        guard case .unreadable = error else {
            Issue.record("expected an unreadable error, got \(error)")
            return
        }
    }
    #expect(try Data(contentsOf: file) == corrupt)
    await opened.session.end()
}
