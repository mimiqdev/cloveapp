import Foundation
import Synchronization
import Testing

import CloveCore

private func makeAccess(storeRoot: URL, scope: ScopeRecorder) -> FolderAccess {
    FolderAccess(
        store: RecentFolderStore(fileURL: storeRoot.appendingPathComponent("recents.json")),
        scope: scope)
}

@Test func endingWaitsForAdmittedWorkToDrain() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let scope = ScopeRecorder()
    let access = makeAccess(storeRoot: storeRoot, scope: scope)
    let opened = try #require(await access.pick(folder).openedFolder)
    let session = opened.session

    let admitted = Mutex(false)
    let gate = AsyncGate()
    let work = Task {
        try await session.withAdmittedWork { () -> Int in
            admitted.withLock { $0 = true }
            await gate.wait()
            return 7
        }
    }
    try await waitUntil { admitted.withLock { $0 } }

    let ending = Task { await session.end() }
    try await waitForCondition { await session.isEnded }
    #expect(scope.stopCount == 0)

    await gate.open()
    #expect(try await work.value == 7)
    await ending.value
    #expect(scope.stopCount == 1)
    #expect(scope.startedURLs.count == 1)
    #expect(scope.stoppedURLs.count == 1)
}

@Test func anEndedSessionRefusesNewWork() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let scope = ScopeRecorder()
    let access = makeAccess(storeRoot: storeRoot, scope: scope)
    let opened = try #require(await access.pick(folder).openedFolder)
    await opened.session.end()
    await opened.session.end()
    #expect(scope.stopCount == 1)

    do {
        _ = try await opened.session.withAdmittedWork { 1 }
        Issue.record("expected the ended session to refuse new work")
    } catch let error as FolderSessionError {
        #expect(error == .ended)
    }
}

@Test func cancelledWorkStillDrainsAndReleasesTheScope() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let scope = ScopeRecorder()
    let access = makeAccess(storeRoot: storeRoot, scope: scope)
    let opened = try #require(await access.pick(folder).openedFolder)
    let session = opened.session

    let admitted = Mutex(false)
    let work = Task {
        try await session.withAdmittedWork {
            admitted.withLock { $0 = true }
            try await Task.sleep(for: .seconds(30))
        }
    }
    try await waitUntil { admitted.withLock { $0 } }
    work.cancel()
    _ = try? await work.value
    #expect(scope.stopCount == 0)

    await session.end()
    #expect(scope.stopCount == 1)
    #expect(scope.startCount == 1)
}

@Test func aFailedStartIsNeverStopped() async throws {
    let storeRoot = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: storeRoot) }
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let missing = folder.appendingPathComponent("gone", isDirectory: true)

    let scope = ScopeRecorder(grantsAccess: false)
    let access = makeAccess(storeRoot: storeRoot, scope: scope)
    let opened = try #require(await access.pick(folder).openedFolder)
    await opened.session.end()
    #expect(scope.startCount == 1)
    #expect(scope.stopCount == 0)

    #expect(await access.pick(missing).failure != nil)
    #expect(scope.startCount == 2)
    #expect(scope.stopCount == 0)
}
